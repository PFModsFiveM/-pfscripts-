// ============================================================================
// Locale Strings - Complete Translations
// ============================================================================
// This file contains all UI strings that should be translated
// Each locale JSON file should include all these keys

const LOCALE_KEYS = {
  // Navigation
  nav_main: "Main",
  nav_records: "Records",
  nav_admin: "Admin",
  nav_dashboard: "Dashboard",
  nav_dispatch: "Dispatch",
  nav_cctv: "CCTV",
  nav_citizens: "Citizens",
  nav_vehicles: "Vehicles",
  nav_warrant: "Warrant",
  nav_weapons: "Weapons",
  nav_reports: "Reports",
  nav_incidents: "Incidents",
  nav_evidence: "Evidence",
  nav_officers: "Officers",
  nav_roster: "Roster",
  nav_sop: "SOP",

  // Pages
  page_dashboard: "Dashboard",
  page_dispatch: "Dispatch",
  page_cctv: "CCTV",
  page_citizens: "Citizens",
  page_vehicles: "Vehicles",
  page_warrant: "Warrant",
  page_weapons: "Weapons",
  page_reports: "Reports",
  page_incidents: "Incidents",
  page_evidence: "Evidence",
  page_officers: "Officers",
  page_roster: "Roster",
  page_sop: "Standard Operating Procedures",
  page_fto: "FTO Reports",

  // Common
  common_save: "Save",
  common_cancel: "Cancel",
  common_close: "Close",
  common_unknown: "Unknown",
  common_officer: "Officer",

  // Topbar / Profile
  topbar_refresh: "Refresh",
  topbar_close: "Close",
  profile_edit_title: "Edit Profile",
  profile_name_placeholder: "Officer Name",
  profile_callsign_placeholder: "e.g. 3A-12",

  // Dashboard
  dashboard_personal_information: "Personal Information",
  dashboard_duty_status: "Duty Status",
  dashboard_status: "Status",
  dashboard_chat: "Chat",
  dashboard_bulletin_board: "Bulletin Board",
  bulletin_create: "Create Bulletin",
  bulletin_title: "Title",
  bulletin_description: "Description",
  bulletin_empty: "No bulletins",
  dashboard_active_warrants: "Active Warrants",
  warrants_empty: "No warrants",
  dashboard_active_units: "Active Units",
  units_empty: "No units",
  dashboard_live_location: "Live Location",
  dashboard_street_name: "Street name",
  unit_phone_number: "Phone number",
  unit_status: "Status",
  chat_type_message: "Type a message...",
  chat_emojis: "Emojis",
  chat_send: "Send",
  chat_you: "You",

  // Duty / Status values
  duty_on_duty: "On Duty",
  duty_off_duty: "Off Duty",
  status_available: "Available",
  status_unavailable: "Unavailable",
  status_busy: "Busy",
  status_on_mission: "On Mission",

  // UI Elements
  tablet_title: "Police MDT",
  cctv_live: "CCTV LIVE",
  cctv_exit_hint: "BACKSPACE to exit",

  // Search Placeholders
  search_placeholder: "Search...",
  search_citizens: "Search by name or ID...",
  search_vehicles: "Search by plate or VIN...",
  search_weapons: "Search by serial number...",
  search_officers: "Search officers...",
  search_sop: "Search SOPs (title, text, category)...",

  // Buttons
  button_accept: "Accept",
  button_decline: "Decline",
  button_complete: "Complete",
  button_cancel: "Cancel",
  button_save: "Save",
  button_delete: "Delete",
  button_edit: "Edit",
  button_new: "New",
  button_close: "Close",
  button_search: "Search",
  button_filter: "Filter",
  button_clear: "Clear",
  button_back: "Back",

  // Statuses
  status_pending: "PENDING",
  status_accepted: "ACCEPTED",
  status_completed: "COMPLETED",
  status_archived: "ARCHIVED",

  // Priorities
  priority_low: "LOW",
  priority_medium: "MEDIUM",
  priority_high: "HIGH",
  priority_critical: "CRITICAL",

  // Dispatch
  dispatch_call: "Call",
  dispatch_calls: "Calls",
  dispatch_units: "Units",
  dispatch_location: "Location",
  dispatch_caller: "Caller",
  dispatch_description: "Description",
  dispatch_priority: "Priority",
  dispatch_status: "Status",
  dispatch_created: "Created",
  dispatch_assigned: "Assigned",
  dispatch_completed: "Completed",

  dispatch_active_calls: "Active Calls",
  dispatch_active: "Active",
  dispatch_autoclear: "Auto-clear",
  dispatch_autoclear_aria: "Auto clear calls",
  dispatch_autoclear_off: "Off",
  dispatch_autoclear_1m: "1 min",
  dispatch_autoclear_2m: "2 min",
  dispatch_autoclear_3m: "3 min",
  dispatch_autoclear_4m: "4 min",
  dispatch_autoclear_5m: "5 min",
  dispatch_zoom_in: "Zoom In",
  dispatch_zoom_out: "Zoom Out",
  dispatch_call_title: "Call Title",
  dispatch_id: "ID",
  dispatch_coords: "Coords",
  button_waypoint: "Waypoint",

  // Dispatch Types
  dispatch_type_speeding: "Speeding Vehicle",
  dispatch_type_shooting: "Shots Fired",
  dispatch_type_carjack: "Vehicle Theft",
  dispatch_type_player_dead: "Person Down",
  dispatch_type_combat: "Combat In Progress",
  dispatch_type_driveby: "Drive By Shooting",
  dispatch_type_explosion: "Explosion Reported",
  dispatch_type_robbery: "Robbery In Progress",
  dispatch_type_assault: "Assault Report",
  dispatch_type_disturbance: "Disturbance",
  dispatch_type_medical: "Medical Emergency",
  dispatch_type_traffic: "Traffic Incident",

  // Locations
  location_cayo: "Cayo Perico",
  location_north_sea: "North Sea",
  location_pacific: "Pacific Ocean",
  location_san_andreas: "San Andreas",
  location_unknown: "Unknown Location",

  // Citizen
  citizen_info: "Citizen Info",
  citizen_id: "ID",
  citizen_name: "Name",
  citizen_dob: "Date of Birth",
  citizen_sex: "Sex",
  citizen_height: "Height",
  citizen_licenses: "Licenses",
  citizen_warrants: "Warrants",
  citizen_records: "Criminal Record",
  citizen_phone: "Phone",
  citizen_address: "Address",

  // Vehicle
  vehicle_info: "Vehicle Info",
  vehicle_plate: "Plate",
  vehicle_vin: "VIN",
  vehicle_model: "Model",
  vehicle_owner: "Owner",
  vehicle_registration: "Registration",
  vehicle_status: "Status",
  vehicle_color: "Color",
  vehicle_insured: "Insured",
  vehicle_inspected: "Inspected",

  // Officer
  officer_name: "Officer",
  officer_callsign: "Callsign",
  officer_rank: "Rank",
  officer_status: "Status",
  officer_badge: "Badge",
  officer_division: "Division",
  officer_duty: "On Duty",
  officer_off_duty: "Off Duty",

  // Warrant
  warrant_info: "Warrant Info",
  warrant_citizen: "Citizen",
  warrant_reason: "Reason",
  warrant_issued: "Issued",
  warrant_status: "Status",
  warrant_active: "Active",
  warrant_served: "Served",
  warrant_expired: "Expired",

  // Weapon
  weapon_info: "Weapon Info",
  weapon_serial: "Serial Number",
  weapon_type: "Type",
  weapon_owner: "Owner",
  weapon_registered: "Registered",
  weapon_status: "Status",
  weapon_legal: "Legal",
  weapon_illegal: "Illegal",
  weapon_confiscated: "Confiscated",

  // Ranks
  rank_police: "Police",
  rank_sheriff: "Sheriff",
  rank_officer: "Officer",
  rank_detective: "Detective",
  rank_sergeant: "Sergeant",
  rank_lieutenant: "Lieutenant",
  rank_captain: "Captain",
  rank_chief: "Chief",
  rank_unknown: "Unknown",

  // Errors
  error_no_access: "You do not have access to the MDT",
  error_failed_load: "Failed to load dispatch calls",
  error_access_denied: "Access Denied",
  error_not_found: "Not Found",
  error_server_error: "Server Error",
  error_timeout: "Request Timeout",
  error_network: "Network Error",

  // Success Messages
  success_saved: "Saved Successfully",
  success_deleted: "Deleted Successfully",
  success_completed: "Completed Successfully",
  success_updated: "Updated Successfully",

  // Confirmations
  confirm_delete: "Are you sure you want to delete this?",
  confirm_complete: "Mark this call as completed?",
  confirm_accept: "Accept this call?",

  // Labels
  label_assigned_units: "Assigned Units",
  label_unit: "Unit",
  label_add_unit: "Add Unit",
  label_remove_unit: "Remove Unit",
  label_notes: "Notes",
  label_add_note: "Add Note",
  label_no_units: "No units assigned",
  label_no_notes: "No notes",

  // Roster
  roster_title: "Roster",
  roster_on_duty: "On Duty",
  roster_off_duty: "Off Duty",
  roster_all: "All Officers",
  roster_search: "Search roster...",
  roster_callsign: "Callsign",
  roster_rank: "Rank",
  roster_status: "Status",
  roster_update: "Update Status",

  // SOP
  sop_title: "Standard Operating Procedures",
  sop_new: "New SOP",
  sop_edit: "Edit SOP",
  sop_delete: "Delete SOP",
  sop_category: "Category",
  sop_title_field: "Title",
  sop_content: "Content",
  sop_search_placeholder: "Search SOPs (title, text, category)...",
  sop_loading: "Loading SOPs...",
  sop_select: "Select an SOP to view details.",

  // Officers
  officers_title: "Officers",
  officers_search: "Search officers...",
  officers_callsign: "Callsign",
  officers_rank: "Rank",
  officers_status: "Status",
  officers_vehicle: "Vehicle",
  officers_gps: "GPS",

  // Menu
  menu_options: "Options",
  menu_actions: "Actions",
  menu_more: "More",

  // Time
  time_just_now: "Just now",
  time_minutes_ago: "minutes ago",
  time_hours_ago: "hours ago",
  time_days_ago: "days ago",
  time_unknown: "Unknown",

  // Units
  unit_officer: "Officer",
  unit_units: "Units",
  unit_arrived: "Arrived",
  unit_en_route: "En Route",
  unit_idle: "Idle",

  // Call Details
  call_details: "Call Details",
  call_type: "Type",
  call_priority: "Priority",
  call_location: "Location",
  call_description: "Description",
  call_caller: "Caller",
  call_units: "Assigned Units",
  call_notes: "Notes",
  call_time_created: "Time Created",
  call_time_accepted: "Time Accepted",
  call_time_completed: "Time Completed",

  // Loading States
  loading: "Loading...",
  loading_data: "Loading data...",
  loading_calls: "Loading calls...",
  loading_citizens: "Loading citizens...",
  loading_vehicles: "Loading vehicles...",
  loading_officers: "Loading officers...",

  // Empty States
  empty_calls: "No active calls",
  empty_citizens: "No citizens found",
  empty_vehicles: "No vehicles found",
  empty_weapons: "No weapons found",
  empty_officers: "No officers found",
  empty_results: "No results found",

  // Modal
  modal_title: "Details",
  modal_close: "Close",
  modal_save: "Save Changes",
  modal_delete: "Delete",

  // Tooltips
  tooltip_accept: "Accept this call",
  tooltip_decline: "Decline this call",
  tooltip_complete: "Mark as completed",
  tooltip_edit: "Edit",
  tooltip_delete: "Delete",
  tooltip_view: "View Details",

  // Validation
  validation_required: "This field is required",
  validation_invalid: "Invalid input",
  validation_min_length: "Minimum length is",
  validation_max_length: "Maximum length is",

  // Export/Print
  export_pdf: "Export as PDF",
  export_csv: "Export as CSV",
  print: "Print",

  // Settings
  settings: "Settings",
  about: "About",
  help: "Help",
  logout: "Logout"
};
