-- Documents: stored on the server per citizen (not in one computer's browser). A document can be
-- shared as a read-only link or as a copy the recipient owns, attached to mail, and signed: a
-- signature records the signer's server identity, the time and a SHA-256 fingerprint of the text,
-- and locks the document so the signed text cannot change afterwards.
--
-- Only the owner hands out read-only links (D.Share, or mail the owner sends). Anyone else who mails
-- a document they can read sends each recipient a read-only snapshot copy of their own, which gives
-- no access to the original. Only the owner and people the owner gave a link to can sign. Once
-- someone other than the owner has signed, the owner's delete only takes it off the owner's own list
-- and the signers keep it: the owner cannot take a signer's link back.

PFCitizen = PFCitizen or {}
PFCitizen.Documents = PFCitizen.Documents or {}
local C = PFCitizen
local D = PFCitizen.Documents
local CFG = CitizenConfig.Documents

local function docRow(id)
    id = C.Int(id, 1)
    if not id then return nil end
    return MySQL.single.await([[SELECT id, owner_cid, title, body, copied_from, locked, owner_hidden,
        UNIX_TIMESTAMP(created_at) AS created, UNIX_TIMESTAMP(updated_at) AS updated
        FROM pf_citizen_documents WHERE id = ? AND deleted_at IS NULL LIMIT 1]], { id })
end

local function shared(id, cid)
    return MySQL.scalar.await('SELECT 1 FROM pf_citizen_document_shares WHERE document_id = ? AND citizenid = ? LIMIT 1', { id, cid }) ~= nil
end

local function signedBy(id, cid)
    return MySQL.scalar.await('SELECT 1 FROM pf_citizen_document_signatures WHERE document_id = ? AND citizenid = ? LIMIT 1', { id, cid }) ~= nil
end

--- Documents a citizen owns and still lists (the per-citizen limit counts these).
local function ownCount(cid)
    return tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM pf_citizen_documents WHERE owner_cid = ? AND deleted_at IS NULL AND owner_hidden = 0', { cid })) or 0
end

-- SQL: `d` (a document) may be signed by the citizen in the next parameter: the owner, or someone the
-- owner (or the server itself) gave a link to. A link someone else handed out does not count.
local MAY_SIGN = [[(d.owner_cid = ? OR EXISTS (SELECT 1 FROM pf_citizen_document_shares h
    WHERE h.document_id = d.id AND h.citizenid = ? AND h.shared_by IN (d.owner_cid, 'system')))]]

--- True when the owner, or the server, gave `cid` access to `doc`.
local function maySign(doc, cid)
    if doc.owner_cid == cid then return true end
    local by = MySQL.scalar.await('SELECT shared_by FROM pf_citizen_document_shares WHERE document_id = ? AND citizenid = ? LIMIT 1', { doc.id, cid })
    return by ~= nil and (by == doc.owner_cid or by == 'system')
end

--- The document if `cid` owns it, it was shared with them or they signed it; nil otherwise.
function D.Readable(cid, id)
    local doc = docRow(id)
    if not doc or not cid then return nil end
    if doc.owner_cid == cid or shared(doc.id, cid) or signedBy(doc.id, cid) then return doc end
    return nil
end

--- A read-only link for `toCid`, for server senders (D.Share and the SendMail export). Player mail goes
--- through D.MailAttachment instead. Never errors; false when there is no document.
function D.ShareInternal(id, toCid, byCid)
    id = C.Int(id, 1)
    if not id or type(toCid) ~= 'string' then return false end
    local owner = MySQL.scalar.await('SELECT owner_cid FROM pf_citizen_documents WHERE id = ? AND deleted_at IS NULL LIMIT 1', { id })
    if not owner then return false end
    if owner == toCid then return true end
    MySQL.update.await('INSERT IGNORE INTO pf_citizen_document_shares (document_id, citizenid, shared_by) VALUES (?, ?, ?)', { id, toCid, tostring(byCid or 'system'):sub(1, 50) })
    return true
end

--- Player mail: true when `byCid` mailing document `id` to `toCid` makes a snapshot copy for them
--- (the sender is not the owner and the recipient cannot read the original already); nil when the
--- document is gone.
function D.MailNeedsCopy(id, toCid, byCid)
    local doc = docRow(id)
    if not doc then return nil end
    if doc.owner_cid == byCid or doc.owner_cid == toCid then return false end
    return D.Readable(toCid, doc.id) == nil
end

--- True when `cid` has room for `n` more documents of their own.
function D.HasRoom(cid, n)
    return ownCount(cid) + (n or 1) <= CFG.MaxPerCitizen
end

--- Player mail: the document id `toCid`'s attachment points at when `byCid` mails document `id`.
--- The owner's mail gives a read-only link to the original. Anyone else's mail gives the recipient a
--- read-only snapshot copy of their own (no access to the original), unless they can read the
--- original already. nil, error when nothing can be attached.
function D.MailAttachment(id, toCid, byCid)
    local doc = docRow(id)
    if not doc or type(toCid) ~= 'string' then return nil, 'not_found' end
    if doc.owner_cid == toCid then return tonumber(doc.id) end
    if doc.owner_cid == byCid then
        D.ShareInternal(doc.id, toCid, byCid)
        return tonumber(doc.id)
    end
    if D.Readable(toCid, doc.id) then return tonumber(doc.id) end
    if not D.HasRoom(toCid, 1) then return nil, 'recipient_full' end
    local copy = tonumber(MySQL.insert.await('INSERT INTO pf_citizen_documents (owner_cid, title, body, copied_from, locked) VALUES (?, ?, ?, ?, 1)',
        { toCid, doc.title, doc.body, doc.id }))
    if not copy then return nil, 'not_stored' end
    C.Push(toCid, 'documents', 'changed', {})
    return copy
end

local function signatures(id)
    local out = {}
    for _, s in ipairs(MySQL.query.await('SELECT citizenid, name, fingerprint, UNIX_TIMESTAMP(signed_at) AS at FROM pf_citizen_document_signatures WHERE document_id = ? ORDER BY signed_at, citizenid', { id }) or {}) do
        out[#out + 1] = { name = s.name, fingerprint = s.fingerprint, at = tonumber(s.at), cid = s.citizenid }
    end
    return out
end

local function me(src)
    local P = C.Player(src)
    return P, P and P.PlayerData.citizenid
end

function D.List(src)
    local P, cid = me(src)
    if not P then return { ok = false, error = 'no_player' } end
    local own = MySQL.query.await([[SELECT d.id, d.title, d.locked, UNIX_TIMESTAMP(d.updated_at) AS updated,
            (SELECT COUNT(*) FROM pf_citizen_document_signatures s WHERE s.document_id = d.id) AS signs,
            (SELECT COUNT(*) FROM pf_citizen_document_shares h WHERE h.document_id = d.id) AS shares
        FROM pf_citizen_documents d WHERE d.owner_cid = ? AND d.deleted_at IS NULL AND d.owner_hidden = 0 ORDER BY d.updated_at DESC, d.id DESC LIMIT ?]],
        { cid, CFG.MaxPerCitizen }) or {}
    local withMe = MySQL.query.await([[SELECT d.id, d.title, d.locked, d.owner_cid, UNIX_TIMESTAMP(d.updated_at) AS updated,
            (SELECT COUNT(*) FROM pf_citizen_document_signatures s WHERE s.document_id = d.id) AS signs
        FROM pf_citizen_document_shares h JOIN pf_citizen_documents d ON d.id = h.document_id
        WHERE h.citizenid = ? AND d.deleted_at IS NULL ORDER BY h.created_at DESC LIMIT 100]], { cid }) or {}
    local mine, others = {}, {}
    for _, r in ipairs(own) do
        mine[#mine + 1] = { id = tonumber(r.id), title = r.title, locked = tonumber(r.locked) == 1, updated = tonumber(r.updated),
            signatures = tonumber(r.signs) or 0, shares = tonumber(r.shares) or 0, own = true }
    end
    local names = {}
    for _, r in ipairs(withMe) do
        if names[r.owner_cid] == nil then local c = C.Citizen(r.owner_cid); names[r.owner_cid] = c and c.name or 'Unknown' end
        others[#others + 1] = { id = tonumber(r.id), title = r.title, locked = tonumber(r.locked) == 1, updated = tonumber(r.updated),
            signatures = tonumber(r.signs) or 0, owner = names[r.owner_cid], own = false }
    end
    return { ok = true, mine = mine, shared = others }
end

function D.Get(src, p)
    local P, cid = me(src)
    if not P then return { ok = false, error = 'no_player' } end
    local doc = D.Readable(cid, p.id)
    if not doc then return { ok = false, error = 'not_found' } end
    local own = doc.owner_cid == cid
    local out = {
        id = tonumber(doc.id), title = doc.title, body = doc.body, locked = tonumber(doc.locked) == 1, own = own,
        created = tonumber(doc.created), updated = tonumber(doc.updated), signatures = signatures(doc.id),
        copiedFrom = tonumber(doc.copied_from),
    }
    local owner = C.Citizen(doc.owner_cid)
    out.owner = owner and owner.name or 'Unknown'
    out.canEdit = own and not out.locked
    out.signedByMe = false
    -- signed by someone other than the owner: the owner's delete only takes it off their own list
    out.othersSigned = false
    local signers = {}
    for _, s in ipairs(out.signatures) do
        if s.cid == cid then out.signedByMe = true end
        if s.cid ~= doc.owner_cid then out.othersSigned = true end
        signers[s.cid] = true
        s.cid = nil
    end
    out.canSign = not out.signedByMe and maySign(doc, cid)
    if own then
        out.hidden = tonumber(doc.owner_hidden) == 1
        out.sharedWith = {}
        for _, r in ipairs(MySQL.query.await('SELECT citizenid FROM pf_citizen_document_shares WHERE document_id = ? ORDER BY created_at LIMIT 50', { doc.id }) or {}) do
            local c = C.Citizen(r.citizenid)
            -- a signer keeps their link: the app shows no "stop sharing" for them
            out.sharedWith[#out.sharedWith + 1] = { cid = r.citizenid, name = c and c.name or r.citizenid, signed = signers[r.citizenid] == true }
        end
    end
    return { ok = true, document = out }
end

function D.Save(src, p)
    local P, cid = me(src)
    if not P then return { ok = false, error = 'no_player' } end
    local title = C.Text(p.title, CFG.MaxTitle)
    if not title then return { ok = false, error = 'no_title' } end
    if p.body ~= nil and type(p.body) ~= 'string' then return { ok = false, error = 'bad_request' } end
    if type(p.body) == 'string' and #p.body > CFG.MaxBody then return { ok = false, error = 'too_long' } end
    local body = C.Text(p.body, CFG.MaxBody, true) or ''
    local id = C.Int(p.id, 1)
    if id then
        local doc = docRow(id)
        if not doc or doc.owner_cid ~= cid then return { ok = false, error = 'not_found' } end
        if tonumber(doc.locked) == 1 then return { ok = false, error = 'locked' } end
        -- the locked check is repeated in the statement: a signature landing meanwhile wins
        local n = MySQL.update.await('UPDATE pf_citizen_documents SET title = ?, body = ?, updated_at = NOW() WHERE id = ? AND owner_cid = ? AND locked = 0 AND deleted_at IS NULL',
            { title, body, id, cid })
        if C.Affected(n) < 1 then return { ok = false, error = 'locked' } end
        return { ok = true, id = id }
    end
    if not D.HasRoom(cid, 1) then return { ok = false, error = 'too_many_documents' } end
    id = MySQL.insert.await('INSERT INTO pf_citizen_documents (owner_cid, title, body) VALUES (?, ?, ?)', { cid, title, body })
    if not id then return { ok = false, error = 'not_stored' } end
    return { ok = true, id = tonumber(id) }
end

--- The owner deletes the document (it leaves everyone's list); someone it was shared with only
--- removes it from their own list. Once someone other than the owner signed it, the owner's delete
--- only takes it off the owner's own list: the signers keep their links to the signed text, the
--- people who did not sign lose theirs.
function D.Delete(src, p)
    local _, cid = me(src)
    local doc = cid and D.Readable(cid, p.id)
    if not doc then return { ok = false, error = 'not_found' } end
    if doc.owner_cid == cid then
        -- one statement, so a signature landing meanwhile keeps the document
        local n = MySQL.update.await([[UPDATE pf_citizen_documents d SET d.deleted_at = NOW()
            WHERE d.id = ? AND d.owner_cid = ? AND d.deleted_at IS NULL
            AND NOT EXISTS (SELECT 1 FROM pf_citizen_document_signatures s WHERE s.document_id = d.id AND s.citizenid <> d.owner_cid)]],
            { doc.id, cid })
        if C.Affected(n) > 0 then
            MySQL.update.await('DELETE FROM pf_citizen_document_shares WHERE document_id = ?', { doc.id })
            return { ok = true, deleted = true }
        end
        MySQL.update.await('UPDATE pf_citizen_documents SET owner_hidden = 1 WHERE id = ? AND owner_cid = ?', { doc.id, cid })
        MySQL.update.await([[DELETE h FROM pf_citizen_document_shares h WHERE h.document_id = ?
            AND NOT EXISTS (SELECT 1 FROM pf_citizen_document_signatures s WHERE s.document_id = h.document_id AND s.citizenid = h.citizenid)]],
            { doc.id })
        return { ok = true, hidden = true }
    end
    MySQL.update.await('DELETE FROM pf_citizen_document_shares WHERE document_id = ? AND citizenid = ?', { doc.id, cid })
    return { ok = true, removed = true }
end

--- Share with another citizen (phone number or citizen id): `mode` 'link' (read-only) or 'copy'.
--- The recipient gets a mail with the document attached.
function D.Share(src, p)
    local P, cid = me(src)
    if not P then return { ok = false, error = 'no_player' } end
    local doc = D.Readable(cid, p.id)
    if not doc then return { ok = false, error = 'not_found' } end
    local mode = p.mode == 'copy' and 'copy' or 'link'
    -- only the owner hands out links; anyone who can read a document may give someone a copy
    if mode == 'link' and doc.owner_cid ~= cid then return { ok = false, error = 'not_owner' } end
    local target, err = C.ResolveRecipient(p.to)
    if not target then return { ok = false, error = err } end
    if target.kind ~= 'person' then return { ok = false, error = 'people_only' } end
    if target.cid == cid then return { ok = false, error = 'self' } end
    if not C.Allow(cid, 'doc:share', CFG.ShareBurst, CFG.ShareRefillSeconds) then return { ok = false, error = 'rate_limited' } end

    local sharedId = tonumber(doc.id)
    if mode == 'copy' then
        if not D.HasRoom(target.cid, 1) then return { ok = false, error = 'recipient_full' } end
        sharedId = tonumber(MySQL.insert.await('INSERT INTO pf_citizen_documents (owner_cid, title, body, copied_from) VALUES (?, ?, ?, ?)',
            { target.cid, doc.title, doc.body, doc.id }))
        if not sharedId then return { ok = false, error = 'not_stored' } end
    else
        D.ShareInternal(doc.id, target.cid, cid)
    end
    local senderName = C.NameOfPlayer(P)
    C.Mail.Send(target.cid, {
        sender = senderName, senderType = 'person', senderCid = cid, senderAddress = C.Mail.MyAddress(P),
        subject = (mode == 'copy' and 'Document copy: ' or 'Shared document: ') .. doc.title,
        message = ('%s %s "%s" with you.'):format(senderName, mode == 'copy' and 'sent you a copy of' or 'shared', doc.title),
        attachments = { { type = 'document', id = sharedId, title = doc.title } },
    }, true)
    return { ok = true, mode = mode, id = sharedId, to = target.name }
end

function D.Unshare(src, p)
    local _, cid = me(src)
    local doc = cid and docRow(p.id)
    local target = C.Token(p.cid, 50)
    if not doc or doc.owner_cid ~= cid or not target then return { ok = false, error = 'not_found' } end
    -- someone who signed keeps the signed document: the signature check is in the statement, so a
    -- signature landing meanwhile wins
    local n = MySQL.update.await([[DELETE h FROM pf_citizen_document_shares h WHERE h.document_id = ? AND h.citizenid = ?
        AND NOT EXISTS (SELECT 1 FROM pf_citizen_document_signatures s WHERE s.document_id = h.document_id AND s.citizenid = h.citizenid)]],
        { doc.id, target })
    if C.Affected(n) > 0 then return { ok = true } end
    if signedBy(doc.id, target) then return { ok = false, error = 'signed' } end
    return { ok = false, error = 'not_found' }
end

--- Signs the document as the calling citizen: its owner, or someone the owner gave a link to. The
--- fingerprint is computed by the database from the stored text, and the document is locked in the
--- same step.
function D.Sign(src, p)
    local P, cid = me(src)
    if not P then return { ok = false, error = 'no_player' } end
    local doc = D.Readable(cid, p.id)
    if not doc then return { ok = false, error = 'not_found' } end
    if not maySign(doc, cid) then return { ok = false, error = 'sign_not_allowed' } end
    -- lock first, so no edit can land between taking the fingerprint and locking; who may sign is
    -- checked again in each statement, so a link taken back meanwhile neither locks nor signs
    if C.Affected(MySQL.update.await('UPDATE pf_citizen_documents d SET d.locked = 1 WHERE d.id = ? AND d.deleted_at IS NULL AND ' .. MAY_SIGN,
            { doc.id, cid, cid })) < 1
        and tonumber(doc.locked) ~= 1 then
        return { ok = false, error = 'not_found' }
    end
    local n = MySQL.update.await([[INSERT IGNORE INTO pf_citizen_document_signatures (document_id, citizenid, name, fingerprint)
        SELECT d.id, ?, ?, SHA2(CONCAT(d.title, '\n', d.body), 256) FROM pf_citizen_documents d WHERE d.id = ? AND d.deleted_at IS NULL AND ]] .. MAY_SIGN,
        { cid, C.NameOfPlayer(P), doc.id, cid, cid })
    if C.Affected(n) < 1 then
        if signedBy(doc.id, cid) then return { ok = false, error = 'already_signed' } end
        return { ok = false, error = 'not_found' }
    end
    if doc.owner_cid ~= cid then
        C.Mail.Send(doc.owner_cid, { sender = 'Documents', senderType = 'system', subject = 'Signed: ' .. doc.title,
            message = ('%s signed "%s".'):format(C.NameOfPlayer(P), doc.title),
            attachments = { { type = 'document', id = tonumber(doc.id), title = doc.title } } }, true)
    end
    return { ok = true, signatures = #signatures(doc.id) }
end
