-- Documents: stored on the server per citizen (not in one computer's browser). A document can be
-- shared as a read-only link or as a copy the recipient owns, attached to mail, and signed: a
-- signature records the signer's server identity, the time and a SHA-256 fingerprint of the text,
-- and locks the document so the signed text cannot change afterwards.

PFCitizen = PFCitizen or {}
PFCitizen.Documents = PFCitizen.Documents or {}
local C = PFCitizen
local D = PFCitizen.Documents
local CFG = CitizenConfig.Documents

local function docRow(id)
    id = C.Int(id, 1)
    if not id then return nil end
    return MySQL.single.await([[SELECT id, owner_cid, title, body, copied_from, locked,
        UNIX_TIMESTAMP(created_at) AS created, UNIX_TIMESTAMP(updated_at) AS updated
        FROM pf_citizen_documents WHERE id = ? AND deleted_at IS NULL LIMIT 1]], { id })
end

local function shared(id, cid)
    return MySQL.scalar.await('SELECT 1 FROM pf_citizen_document_shares WHERE document_id = ? AND citizenid = ? LIMIT 1', { id, cid }) ~= nil
end

--- The document if `cid` owns it or it was shared with them; nil otherwise.
function D.Readable(cid, id)
    local doc = docRow(id)
    if not doc or not cid then return nil end
    if doc.owner_cid == cid or shared(doc.id, cid) then return doc end
    return nil
end

--- A read-only link for `toCid` (mail attachments use it). Never errors; false when there is no document.
function D.ShareInternal(id, toCid, byCid)
    id = C.Int(id, 1)
    if not id or type(toCid) ~= 'string' then return false end
    local owner = MySQL.scalar.await('SELECT owner_cid FROM pf_citizen_documents WHERE id = ? AND deleted_at IS NULL LIMIT 1', { id })
    if not owner then return false end
    if owner == toCid then return true end
    MySQL.update.await('INSERT IGNORE INTO pf_citizen_document_shares (document_id, citizenid, shared_by) VALUES (?, ?, ?)', { id, toCid, tostring(byCid or 'system'):sub(1, 50) })
    return true
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
        FROM pf_citizen_documents d WHERE d.owner_cid = ? AND d.deleted_at IS NULL ORDER BY d.updated_at DESC, d.id DESC LIMIT ?]],
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
    for _, s in ipairs(out.signatures) do
        if s.cid == cid then out.signedByMe = true end
        s.cid = nil
    end
    if own then
        out.sharedWith = {}
        for _, r in ipairs(MySQL.query.await('SELECT citizenid FROM pf_citizen_document_shares WHERE document_id = ? ORDER BY created_at LIMIT 50', { doc.id }) or {}) do
            local c = C.Citizen(r.citizenid)
            out.sharedWith[#out.sharedWith + 1] = { cid = r.citizenid, name = c and c.name or r.citizenid }
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
    local count = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM pf_citizen_documents WHERE owner_cid = ? AND deleted_at IS NULL', { cid })) or 0
    if count >= CFG.MaxPerCitizen then return { ok = false, error = 'too_many_documents' } end
    id = MySQL.insert.await('INSERT INTO pf_citizen_documents (owner_cid, title, body) VALUES (?, ?, ?)', { cid, title, body })
    if not id then return { ok = false, error = 'not_stored' } end
    return { ok = true, id = tonumber(id) }
end

--- The owner deletes the document (it leaves everyone's list); someone it was shared with only
--- removes it from their own list.
function D.Delete(src, p)
    local _, cid = me(src)
    local doc = cid and D.Readable(cid, p.id)
    if not doc then return { ok = false, error = 'not_found' } end
    if doc.owner_cid == cid then
        MySQL.update.await('UPDATE pf_citizen_documents SET deleted_at = NOW() WHERE id = ? AND owner_cid = ?', { doc.id, cid })
        MySQL.update.await('DELETE FROM pf_citizen_document_shares WHERE document_id = ?', { doc.id })
        return { ok = true, deleted = true }
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
        local count = tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM pf_citizen_documents WHERE owner_cid = ? AND deleted_at IS NULL', { target.cid })) or 0
        if count >= CFG.MaxPerCitizen then return { ok = false, error = 'recipient_full' } end
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
    local n = MySQL.update.await('DELETE FROM pf_citizen_document_shares WHERE document_id = ? AND citizenid = ?', { doc.id, target })
    return { ok = C.Affected(n) > 0, error = C.Affected(n) > 0 and nil or 'not_found' }
end

--- Signs the document as the calling citizen. The fingerprint is computed by the database from the
--- stored text, and the document is locked in the same step.
function D.Sign(src, p)
    local P, cid = me(src)
    if not P then return { ok = false, error = 'no_player' } end
    local doc = D.Readable(cid, p.id)
    if not doc then return { ok = false, error = 'not_found' } end
    local n = MySQL.update.await([[INSERT IGNORE INTO pf_citizen_document_signatures (document_id, citizenid, name, fingerprint)
        SELECT id, ?, ?, SHA2(CONCAT(title, '\n', body), 256) FROM pf_citizen_documents WHERE id = ? AND deleted_at IS NULL]],
        { cid, C.NameOfPlayer(P), doc.id })
    if C.Affected(n) < 1 then return { ok = false, error = 'already_signed' } end
    MySQL.update.await('UPDATE pf_citizen_documents SET locked = 1 WHERE id = ?', { doc.id })
    if doc.owner_cid ~= cid then
        C.Mail.Send(doc.owner_cid, { sender = 'Documents', senderType = 'system', subject = 'Signed: ' .. doc.title,
            message = ('%s signed "%s".'):format(C.NameOfPlayer(P), doc.title),
            attachments = { { type = 'document', id = tonumber(doc.id), title = doc.title } } }, true)
    end
    return { ok = true, signatures = #signatures(doc.id) }
end
