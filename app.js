/* CONFIGURACIÓ SUPABASE: posa la URL i la clau pública del teu projecte. */
const SUPABASE_URL = "https://magfiztbufddyhutptdd.supabase.co";
const SUPABASE_ANON_KEY = "sb_publishable_yINpI3MnA7jWaLLROmechw_7K0GqwwR";

const isConfigured = SUPABASE_URL.startsWith("https://") && !SUPABASE_URL.includes("POSA_AQUI") && !SUPABASE_ANON_KEY.includes("POSA_AQUI") && !SUPABASE_ANON_KEY.startsWith("sb_secret_");
const db = isConfigured ? window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY) : null;

const ids = ["employeeCode","toggleCodeBtn","entryBtn","exitBtn","resultCard","resultIcon","resultTitle","resultText","connectionDot","connectionText","currentDate","currentTime","adminEmail","adminPassword","adminLoginBtn","adminLogin","adminPanel","adminUser","recordsBody","employeesBody","refreshBtn","exportBtn","exportSummaryBtn","logoutBtn","employeeSearch","employeeFilter","monthFilter","dayFilter","typeFilter","clearFiltersBtn","recordCount","employeeForm","editingEmployeeId","employeeName","employeeAdminCode","employeeActive","saveEmployeeBtn","cancelEditEmployeeBtn","employeeListSearch","employeeSort","employeeCount","employeeMonthSummary","summaryPlaceholder","summaryContent","summaryEmployeeName","summaryMonthLabel","summaryTotalHours","summaryWorkedDays","workCalendar","dailySummaryBody","bulkProgress","bulkProgressTitle","bulkProgressText","cancelBulkBtn","punchEditorCategory","punchEditorForm","editPunchEmployee","editPunchDate","editPunchEntry1","editPunchExit1","editPunchEntry2","editPunchExit2","editPunchHours","editPunchReason","loadPunchDayBtn","savePunchDayBtn","clearPunchDayBtn","batchStartDate","batchEndDate","batchEntry1","batchExit1","batchEntry2","batchExit2","batchReason","createBatchDaysBtn","weekdayPicker","employeeDocument","workerPortalDetails","workerPortalLogin","workerPortalCode","workerPortalMonth","workerPortalBtn","workerPortalPanel","workerPortalName","workerPortalMonthLabel","workerPortalHours","workerPortalDays","workerPortalCalendar","workerPortalRecords","workerPortalCloseBtn","batchAllActive","autoPunchStatus","autoPunchEnabled","autoPunchEntry1","autoPunchExit1","autoPunchEntry2","autoPunchExit2","saveAutoPunchBtn","notificationBtn","editCalendarMonth","editPunchCalendar","editSelectedDate","editFullDayBtn","editHalfDayBtn","editPunchExit1Label","editPunchEntry2Label","editPunchExit2Label"];
const els = Object.fromEntries(ids.map(id => [id, document.getElementById(id)]));

let currentRecords = [];
let filteredRecords = [];
let employees = [];
let employeeStatus = "all";
let currentAdminEmail = "";
let cancelBulkRequested = false;
let activeBulkJobId = localStorage.getItem("pcm_active_bulk_job") || "";
let bulkPollTimer = null;
const PRIMARY_ADMIN_EMAIL = "admin@pcmfruits.com";

function updateClock() {
  const now = new Date();
  els.currentTime.textContent = now.toLocaleTimeString("ca-ES", { hour: "2-digit", minute: "2-digit", second: "2-digit" });
  els.currentDate.textContent = now.toLocaleDateString("ca-ES", { weekday: "long", day: "numeric", month: "long", year: "numeric" });
}
function setConnection(ok, text) { els.connectionDot.classList.toggle("online", ok); els.connectionDot.classList.toggle("offline", !ok); els.connectionText.textContent = text; }
function showResult(ok, title, text) { els.resultCard.classList.add("hidden"); void els.resultCard.offsetWidth; els.resultCard.classList.remove("hidden"); els.resultCard.classList.toggle("error", !ok); els.resultIcon.textContent = ok ? "✓" : "!"; els.resultTitle.textContent = title; els.resultText.textContent = text; clearTimeout(showResult.timer); showResult.timer = setTimeout(() => els.resultCard.classList.add("hidden"), 7000); }
function setBusy(busy) { els.entryBtn.disabled = busy; els.exitBtn.disabled = busy; }

async function verifyConnection() {
  if (!db) return setConnection(false, "Falta configurar Supabase a app.js");
  const { error } = await db.from("empleats").select("id").limit(1);
  setConnection(!error, error ? `Error de connexió: ${error.message}` : "Connectat a Supabase");
}

function parseCodeRange(value) {
  const clean = value.trim();
  const match = clean.match(/^(\d+)\s*-\s*(\d+)$/);
  if (!match) return null;
  const first = Number(match[1]);
  const last = Number(match[2]);
  if (!Number.isInteger(first) || !Number.isInteger(last) || first < 1 || last < first || last - first > 199) return [];
  return { first, last, total: last - first + 1 };
}
async function registerSinglePunch(code, type) {
  const { data, error } = await db.rpc("registrar_fitxatge", { p_codi: code, p_tipus: type });
  if (error) throw error;
  return Array.isArray(data) ? data[0] : data;
}
async function startServerBulkPunch(range, type) {
  const { data, error } = await db.rpc("iniciar_fitxatge_grup_servidor", {
    p_codi_inici: range.first,
    p_codi_fi: range.last,
    p_tipus: type
  });
  if (error) throw error;
  const row = Array.isArray(data) ? data[0] : data;
  activeBulkJobId = row.job_id;
  localStorage.setItem("pcm_active_bulk_job", activeBulkJobId);
  els.bulkProgress.classList.add("server-job");
  els.bulkProgress.classList.remove("hidden");
  els.bulkProgressTitle.textContent = `${type === "entrada" ? "Entrades" : "Sortides"} en grup al servidor`;
  els.bulkProgressText.textContent = `${row.total_actius ?? 0} actius en cua · ${row.omitits ?? 0} inactius o inexistents omesos. Pots tancar l’aplicació.`;
  monitorBulkJob(activeBulkJobId, true);
  return row;
}
async function monitorBulkJob(jobId, immediate = false) {
  clearTimeout(bulkPollTimer);
  if (!jobId || !db) return;
  const run = async () => {
    const { data, error } = await db.rpc("estat_fitxatge_grup_servidor", { p_job_id: jobId });
    if (error) {
      els.bulkProgressText.textContent = `No s'ha pogut consultar el procés: ${error.message}`;
      bulkPollTimer = setTimeout(run, 10000);
      return;
    }
    const row = Array.isArray(data) ? data[0] : data;
    if (!row) {
      localStorage.removeItem("pcm_active_bulk_job");
      activeBulkJobId = "";
      els.bulkProgress.classList.add("hidden");
      return;
    }
    els.bulkProgress.classList.remove("hidden");
    els.bulkProgress.classList.add("server-job");
    els.bulkProgressTitle.textContent = `Fitxatge en grup · ${row.estat}`;
    els.bulkProgressText.textContent = `${row.processats}/${row.total} processats · ${row.correctes} correctes · ${row.errors} errors · ${row.omesos} omesos`;
    if (["completat","cancel_lada","error"].includes(row.estat)) {
      localStorage.removeItem("pcm_active_bulk_job");
      activeBulkJobId = "";
      const ok = row.estat === "completat" && Number(row.errors) === 0;
      showResult(ok, "Fitxatge en grup finalitzat", `${row.correctes} correctes · ${row.errors} errors · ${row.omesos} omesos.`);
      notifyUser("PCM Fruits · Fitxatge en grup", `${row.correctes} correctes, ${row.errors} errors i ${row.omesos} omesos.`);
      setTimeout(() => els.bulkProgress.classList.add("hidden"), 8000);
      return;
    }
    bulkPollTimer = setTimeout(run, 5000);
  };
  if (immediate) await run(); else bulkPollTimer = setTimeout(run, 1500);
}
async function registerPunch(type) {
  const raw = els.employeeCode.value.trim();
  if (!raw) return showResult(false, "Falta el codi", "Introdueix el codi de treballador abans de fitxar.");
  if (!db) return showResult(false, "Supabase no configurat", "Obre app.js i posa la URL i la clau pública del projecte.");
  const range = parseCodeRange(raw);
  if (range && range.total === 0) return showResult(false, "Rang incorrecte", "Escriu un rang vàlid, per exemple 1-35. El màxim és de 200 codis.");
  if (!range) {
    setBusy(true);
    try {
      const record = await registerSinglePunch(raw, type);
      const stamp = new Date(record.data_hora).toLocaleString("ca-ES", { timeZone: "Europe/Madrid", dateStyle: "short", timeStyle: "medium" });
      showResult(true, type === "entrada" ? "Entrada registrada" : "Sortida registrada", `${record.nom} · ${stamp}`);
      els.employeeCode.value = ""; els.employeeCode.focus();
    } catch (error) { showResult(false, "No s'ha pogut registrar", humanizeError(error.message)); }
    finally { setBusy(false); }
    return;
  }
  if (!window.confirm(`Es crearà una cua al servidor per als codis ${range.first}-${range.last}. Continuarà encara que tanquis l'aplicació. Vols continuar?`)) return;
  setBusy(true);
  try {
    const row = await startServerBulkPunch(range, type);
    showResult(true, "Fitxatge en grup iniciat", `${row.total_actius ?? 0} empleats actius en cua. Pots tancar l'aplicació.`);
    els.employeeCode.value = "";
  } catch (error) {
    showResult(false, "No s'ha pogut iniciar", humanizeError(error.message));
  } finally { setBusy(false); }
}
function humanizeError(message = "") { if (message.includes("CODI_INCORRECTE")) return "El codi no correspon a cap treballador actiu."; if (message.includes("FITXATGE_DUPLICAT")) return "Aquest treballador ja ha registrat aquest mateix tipus consecutivament."; return message || "S'ha produït un error inesperat."; }

async function adminLogin() {
  if (!db) return showResult(false, "Supabase no configurat", "Configura el projecte abans d'entrar.");
  const email = els.adminEmail.value.trim(), password = els.adminPassword.value;
  if (!email || !password) return showResult(false, "Dades incompletes", "Escriu el correu i la contrasenya.");
  els.adminLoginBtn.disabled = true;
  const { data, error } = await db.auth.signInWithPassword({ email, password });
  els.adminLoginBtn.disabled = false;
  if (error) return showResult(false, "Accés denegat", error.message);
  openAdmin(data.user.email); await loadAdminData();
}
function openAdmin(email) {
  currentAdminEmail = String(email || "").toLowerCase();
  els.adminUser.textContent = email;
  els.adminLogin.classList.add("hidden");
  els.adminPanel.classList.remove("hidden");
  els.punchEditorCategory.classList.toggle("hidden", currentAdminEmail !== PRIMARY_ADMIN_EMAIL);
}

async function loadAdminData() {
  await Promise.all([loadEmployees(), loadRecords()]);
  if (currentAdminEmail === PRIMARY_ADMIN_EMAIL) await loadAutoPunchConfig();
}
async function loadEmployees() {
  els.employeesBody.innerHTML = '<tr><td colspan="6" class="empty-row">Carregant...</td></tr>';
  const { data, error } = await db.from("empleats").select("id,nom,codi,dni_nie,actiu,created_at").order("nom");
  if (error) { els.employeesBody.innerHTML = `<tr><td colspan="4" class="empty-row">${escapeHtml(error.message)}</td></tr>`; return; }
  employees = data || [];
  els.employeeFilter.innerHTML = '<option value="">Tots els empleats</option>' + employees.map(e => `<option value="${e.id}">${escapeHtml(e.nom)} (${escapeHtml(e.codi)})</option>`).join("");
  els.editPunchEmployee.innerHTML = '<option value="">Selecciona un empleat</option>' + employees.map(e => `<option value="${e.id}">${escapeHtml(e.nom)} (${escapeHtml(e.codi)})</option>`).join("");
  renderEmployees();
  applyFilters();
  renderEditPunchCalendar();
}
function renderEmployees() {
  const search = els.employeeListSearch.value.trim().toLowerCase();
  const list = employees.filter(e => {
    const statusOk = employeeStatus === "all" || (employeeStatus === "active" ? e.actiu : !e.actiu);
    const searchOk = !search || e.nom.toLowerCase().includes(search) || String(e.codi).toLowerCase().includes(search);
    return statusOk && searchOk;
  });

  const sortMode = els.employeeSort.value;
  list.sort((a, b) => {
    if (sortMode === "id-desc") return Number(b.id) - Number(a.id);
    if (sortMode === "name-asc") return a.nom.localeCompare(b.nom, "ca", { sensitivity: "base" });
    if (sortMode === "name-desc") return b.nom.localeCompare(a.nom, "ca", { sensitivity: "base" });
    return Number(a.id) - Number(b.id);
  });
  const totalEmployees = employees.length;
  const activeEmployees = employees.filter(e => e.actiu).length;
  const inactiveEmployees = totalEmployees - activeEmployees;
  const allCountEl = document.getElementById("employeeStatusAllCount");
  const activeCountEl = document.getElementById("employeeStatusActiveCount");
  const inactiveCountEl = document.getElementById("employeeStatusInactiveCount");
  if (allCountEl) allCountEl.textContent = totalEmployees;
  if (activeCountEl) activeCountEl.textContent = activeEmployees;
  if (inactiveCountEl) inactiveCountEl.textContent = inactiveEmployees;

  els.employeeCount.textContent = `${list.length} ${list.length === 1 ? "empleat" : "empleats"}`;
  els.employeesBody.innerHTML = list.length ? list.map(e => `<tr>
    <td>${escapeHtml(e.nom)}</td>
    <td>${escapeHtml(e.codi)}</td>
    <td>${escapeHtml(e.dni_nie || "—")}</td>
    <td><span class="badge ${e.actiu ? "active-status" : "inactive-status"}">${e.actiu ? "Actiu" : "Inactiu"}</span></td>
    <td>${new Date(e.created_at).toLocaleDateString("ca-ES", { timeZone: "Europe/Madrid" })}</td>
    <td><div class="row-actions">
      <button type="button" class="mini-btn" data-edit-employee="${e.id}">Editar</button>
      <button type="button" class="mini-btn ${e.actiu ? "danger-text" : "success-text"}" data-toggle-employee="${e.id}">${e.actiu ? "Desactivar" : "Activar"}</button>
    </div></td>
  </tr>`).join("") : '<tr><td colspan="6" class="empty-row">No hi ha empleats amb aquests filtres.</td></tr>';
}

function resetEmployeeForm() {
  els.employeeForm.reset();
  els.editingEmployeeId.value = "";
  els.employeeActive.value = "true";
  els.saveEmployeeBtn.textContent = "Crear empleat";
  els.cancelEditEmployeeBtn.classList.add("hidden");
}

function editEmployee(id) {
  const employee = employees.find(e => String(e.id) === String(id));
  if (!employee) return;
  els.editingEmployeeId.value = employee.id;
  els.employeeName.value = employee.nom;
  els.employeeAdminCode.value = employee.codi;
  els.employeeActive.value = String(employee.actiu);
  els.employeeDocument.value = employee.dni_nie || "";
  els.saveEmployeeBtn.textContent = "Guardar canvis";
  els.cancelEditEmployeeBtn.classList.remove("hidden");
  els.employeeName.focus();
  els.employeeForm.scrollIntoView({ behavior: "smooth", block: "center" });
}

async function saveEmployee(event) {
  event.preventDefault();
  const id = els.editingEmployeeId.value;
  const nom = els.employeeName.value.trim();
  const codi = els.employeeAdminCode.value.trim();
  const actiu = els.employeeActive.value === "true";
  const dni_nie = els.employeeDocument.value.trim().toUpperCase() || null;
  if (!nom || !codi) return showResult(false, "Dades incompletes", "Escriu el nom i el codi del treballador.");
  els.saveEmployeeBtn.disabled = true;
  try {
    const { data, error } = await db.rpc("admin_guardar_empleat", {
      p_id: id ? Number(id) : null,
      p_nom: nom,
      p_codi: codi,
      p_dni_nie: dni_nie,
      p_actiu: actiu
    });
    if (error) throw error;
    const savedEmployee = Array.isArray(data) ? data[0] : data;
    if (!savedEmployee?.id) throw new Error("No s'ha pogut confirmar l'actualització de l'empleat.");
    showResult(true, id ? "Empleat actualitzat" : "Empleat creat", `${nom} · codi ${codi}`);
    resetEmployeeForm();
    await loadEmployees();
    applyFilters();
  } catch (error) {
    const duplicate = error.message?.includes("duplicate key") || error.code === "23505";
    showResult(false, "No s'ha pogut guardar", duplicate ? "Aquest codi o DNI/NIE ja està assignat a un altre empleat." : error.message);
  } finally {
    els.saveEmployeeBtn.disabled = false;
  }
}

async function toggleEmployee(id) {
  const employee = employees.find(e => String(e.id) === String(id));
  if (!employee) return;
  const action = employee.actiu ? "desactivar" : "activar";
  if (!window.confirm(`Vols ${action} ${employee.nom}?`)) return;
  const { error } = await db.rpc("admin_canviar_estat_empleat", { p_empleat_id: Number(employee.id), p_actiu: !employee.actiu });
  if (error) return showResult(false, "No s'ha pogut actualitzar", humanizeError(error.message));
  showResult(true, employee.actiu ? "Empleat desactivat" : "Empleat activat", employee.nom);
  await loadEmployees();
  applyFilters();
}

async function loadRecords() {
  els.recordsBody.innerHTML = '<tr><td colspan="5" class="empty-row">Carregant...</td></tr>';
  const { data, error } = await db.from("vista_fitxatges").select("id,data_hora,tipus,nom,codi").order("data_hora", { ascending: false }).limit(10000);
  if (error) { els.recordsBody.innerHTML = `<tr><td colspan="5" class="empty-row">${escapeHtml(error.message)}</td></tr>`; return; }
  currentRecords = data || []; applyFilters(); renderEditPunchCalendar();
}
function localParts(iso) {
  const parts = new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Madrid", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit", hourCycle: "h23" }).formatToParts(new Date(iso));
  return Object.fromEntries(parts.map(p => [p.type, p.value]));
}
function applyFilters() {
  const search = els.employeeSearch.value.trim().toLowerCase();
  const employeeId = els.employeeFilter.value;
  const selectedEmployee = employees.find(e => String(e.id) === employeeId);
  const month = els.monthFilter.value, day = els.dayFilter.value, type = els.typeFilter.value;
  filteredRecords = currentRecords.filter(r => {
    const p = localParts(r.data_hora); const recordMonth = `${p.year}-${p.month}`;
    return (!search || r.nom.toLowerCase().includes(search) || String(r.codi).toLowerCase().includes(search)) && (!selectedEmployee || String(r.codi) === String(selectedEmployee.codi)) && (!month || recordMonth === month) && (!day || Number(p.day) === Number(day)) && (!type || r.tipus === type);
  });
  renderRecords();
  renderEmployeeMonthSummary();
}

function getSummaryEmployee() {
  const selectedId = els.employeeFilter.value;
  if (selectedId) return employees.find(e => String(e.id) === String(selectedId)) || null;

  const query = els.employeeSearch.value.trim().toLowerCase();
  if (!query) return null;
  const exact = employees.filter(e => e.nom.toLowerCase() === query || String(e.codi).toLowerCase() === query);
  if (exact.length === 1) return exact[0];
  const matches = employees.filter(e => e.nom.toLowerCase().includes(query) || String(e.codi).toLowerCase().includes(query));
  return matches.length === 1 ? matches[0] : null;
}

function monthInfo() {
  const value = els.monthFilter.value;
  if (value && /^\d{4}-\d{2}$/.test(value)) {
    const [year, month] = value.split("-").map(Number);
    return { year, month };
  }
  const now = new Date();
  return { year: now.getFullYear(), month: now.getMonth() + 1 };
}

function calculateDailyWork(records) {
  const sorted = records.slice().sort((a, b) => new Date(a.data_hora) - new Date(b.data_hora));
  const groups = new Map();
  sorted.forEach(record => {
    const p = localParts(record.data_hora);
    const key = `${p.year}-${p.month}-${p.day}`;
    if (!groups.has(key)) groups.set(key, { key, day: Number(p.day), records: [], totalMs: 0, firstEntry: null, lastExit: null });
    groups.get(key).records.push(record);
  });

  for (const group of groups.values()) {
    let openEntry = null;
    for (const record of group.records) {
      const date = new Date(record.data_hora);
      if (record.tipus === "entrada") {
        if (!group.firstEntry) group.firstEntry = date;
        openEntry = date;
      } else if (record.tipus === "sortida") {
        group.lastExit = date;
        if (openEntry && date >= openEntry) {
          group.totalMs += date - openEntry;
          openEntry = null;
        }
      }
    }
  }
  return [...groups.values()].sort((a, b) => a.key.localeCompare(b.key));
}

function renderEmployeeMonthSummary() {
  const employee = getSummaryEmployee();
  if (!employee) {
    els.summaryPlaceholder.classList.remove("hidden");
    els.summaryContent.classList.add("hidden");
    return;
  }

  const { year, month } = monthInfo();
  const monthString = `${year}-${String(month).padStart(2, "0")}`;
  const employeeRecords = currentRecords.filter(record => {
    const p = localParts(record.data_hora);
    return String(record.codi) === String(employee.codi) && `${p.year}-${p.month}` === monthString;
  });
  const daily = calculateDailyWork(employeeRecords);
  const totalMs = daily.reduce((sum, day) => sum + day.totalMs, 0);

  els.summaryPlaceholder.classList.add("hidden");
  els.summaryContent.classList.remove("hidden");
  els.summaryEmployeeName.textContent = `${employee.nom} · ${employee.codi}`;
  els.summaryMonthLabel.textContent = new Intl.DateTimeFormat("ca-ES", { month: "long", year: "numeric" }).format(new Date(year, month - 1, 1));
  els.summaryTotalHours.textContent = formatDurationWords(totalMs);
  els.summaryWorkedDays.textContent = `${daily.length} ${daily.length === 1 ? "dia treballat" : "dies treballats"}`;

  renderWorkCalendar(year, month, daily);
  renderDailySummary(daily);
}

function renderWorkCalendar(year, month, daily) {
  const workedByDay = new Map(daily.map(item => [item.day, item]));
  const daysInMonth = new Date(year, month, 0).getDate();
  const mondayIndex = (new Date(year, month - 1, 1).getDay() + 6) % 7;
  const cells = [];
  for (let i = 0; i < mondayIndex; i++) cells.push('<span class="calendar-day empty" aria-hidden="true"></span>');
  for (let day = 1; day <= daysInMonth; day++) {
    const work = workedByDay.get(day);
    const classes = work ? "calendar-day worked" : "calendar-day";
    const title = work ? `${formatDurationWords(work.totalMs)} · ${work.records.length} fitxatges` : "Sense fitxatges";
    cells.push(`<span class="${classes}" title="${escapeHtml(title)}"><b>${day}</b>${work ? `<small>${formatDurationCompact(work.totalMs)}</small>` : ""}</span>`);
  }
  els.workCalendar.innerHTML = cells.join("");
}

function renderDailySummary(daily) {
  if (!daily.length) {
    els.dailySummaryBody.innerHTML = '<tr><td colspan="5" class="empty-row">Aquest treballador no té fitxatges durant el mes seleccionat.</td></tr>';
    return;
  }
  els.dailySummaryBody.innerHTML = daily.map(item => `<tr>
    <td>${item.key.split("-").reverse().join("/")}</td>
    <td>${item.firstEntry ? formatTime(item.firstEntry) : "—"}</td>
    <td>${item.lastExit ? formatTime(item.lastExit) : "—"}</td>
    <td><strong>${formatDurationWords(item.totalMs)}</strong></td>
    <td>${item.records.length}</td>
  </tr>`).join("");
}

function formatDurationWords(ms) {
  const minutes = Math.floor(ms / 60000);
  const hours = Math.floor(minutes / 60);
  return `${hours} h ${String(minutes % 60).padStart(2, "0")} min`;
}

function formatDurationCompact(ms) {
  const minutes = Math.floor(ms / 60000);
  return `${Math.floor(minutes / 60)}:${String(minutes % 60).padStart(2, "0")}`;
}

function renderRecords() {
  els.recordCount.textContent = `${filteredRecords.length} ${filteredRecords.length === 1 ? "registre" : "registres"}`;
  if (!filteredRecords.length) { els.recordsBody.innerHTML = '<tr><td colspan="5" class="empty-row">No hi ha fitxatges amb aquests filtres.</td></tr>'; return; }
  els.recordsBody.innerHTML = filteredRecords.map(r => { const p = localParts(r.data_hora); const date = `${p.day}/${p.month}/${p.year}`; const time = `${p.hour}:${p.minute}:${p.second}`; return `<tr><td>${date}</td><td>${time}</td><td>${escapeHtml(r.nom)}</td><td>${escapeHtml(r.codi)}</td><td><span class="badge ${r.tipus === "entrada" ? "entry" : "exit"}">${escapeHtml(r.tipus)}</span></td></tr>`; }).join("");
}

function downloadCsv(rows, filename) {
  const csv = "\uFEFF" + rows.map(row => row.map(csvCell).join(";")).join("\n");
  const url = URL.createObjectURL(new Blob([csv], { type: "text/csv;charset=utf-8" }));
  const a = document.createElement("a"); a.href = url; a.download = filename; a.click(); setTimeout(() => URL.revokeObjectURL(url), 1000);
}
function exportCsv() {
  if (!filteredRecords.length) return showResult(false, "Sense dades", "No hi ha fitxatges per exportar.");
  const rows = [["Data", "Hora", "Treballador", "Codi", "Tipus"]];
  filteredRecords.slice().reverse().forEach(r => { const p = localParts(r.data_hora); rows.push([`${p.day}/${p.month}/${p.year}`, `${p.hour}:${p.minute}:${p.second}`, r.nom, r.codi, r.tipus]); });
  const employee = els.employeeFilter.options[els.employeeFilter.selectedIndex]?.text || "tots";
  downloadCsv(rows, `fitxatges-${safeFilename(employee)}-${els.monthFilter.value || "totes-dates"}${els.dayFilter.value ? `-dia-${els.dayFilter.value}` : ""}.csv`);
}
function exportDailySummary() {
  const source = filteredRecords.slice().sort((a,b) => new Date(a.data_hora) - new Date(b.data_hora));
  if (!source.length) return showResult(false, "Sense dades", "No hi ha fitxatges per resumir.");
  const groups = new Map();
  source.forEach(r => { const p = localParts(r.data_hora); const date = `${p.year}-${p.month}-${p.day}`; const key = `${r.codi}|${date}`; if (!groups.has(key)) groups.set(key, { nom:r.nom,codi:r.codi,date,records:[] }); groups.get(key).records.push(r); });
  const rows = [["Data", "Treballador", "Codi", "Primera entrada", "Última sortida", "Hores totals", "Núm. fitxatges"]];
  [...groups.values()].sort((a,b) => a.date.localeCompare(b.date) || a.nom.localeCompare(b.nom)).forEach(g => {
    let open = null, totalMs = 0; const entries = [], exits = [];
    g.records.forEach(r => { const d = new Date(r.data_hora); if (r.tipus === "entrada") { entries.push(d); open = d; } else { exits.push(d); if (open) { totalMs += d - open; open = null; } } });
    rows.push([g.date.split("-").reverse().join("/"), g.nom, g.codi, entries.length ? formatTime(entries[0]) : "", exits.length ? formatTime(exits[exits.length-1]) : "", formatDuration(totalMs), g.records.length]);
  });
  downloadCsv(rows, `resum-diari-${els.monthFilter.value || "totes-dates"}.csv`);
}
function formatTime(date) { return date.toLocaleTimeString("ca-ES", { timeZone:"Europe/Madrid", hour:"2-digit", minute:"2-digit", second:"2-digit" }); }
function formatDuration(ms) { const mins = Math.floor(ms / 60000); return `${Math.floor(mins/60)}:${String(mins%60).padStart(2,"0")}`; }
function safeFilename(v) { return String(v).normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[^a-zA-Z0-9_-]+/g, "-").replace(/^-|-$/g, "").toLowerCase(); }
function csvCell(value) { return `"${String(value ?? "").replaceAll('"', '""')}"`; }
function escapeHtml(value) { return String(value ?? "").replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;").replaceAll("'", "&#039;"); }

function clearFilters() { els.employeeSearch.value = ""; els.employeeFilter.value = ""; els.dayFilter.value = ""; els.typeFilter.value = ""; setCurrentMonth(); applyFilters(); }
function setCurrentMonth() { const now = new Date(); els.monthFilter.value = `${now.getFullYear()}-${String(now.getMonth()+1).padStart(2,"0")}`; }
async function logout() { await db.auth.signOut(); currentAdminEmail = ""; els.adminPanel.classList.add("hidden"); els.adminLogin.classList.remove("hidden"); els.adminPassword.value = ""; els.punchEditorCategory.classList.add("hidden"); }
async function restoreSession() { if (!db) return; const { data } = await db.auth.getSession(); if (data.session?.user) { openAdmin(data.session.user.email); await loadAdminData(); } }


function assertPrimaryAdmin() {
  if (currentAdminEmail !== PRIMARY_ADMIN_EMAIL) {
    showResult(false, "Accés restringit", "Aquesta funció només està disponible per a admin@pcmfruits.com.");
    return false;
  }
  return true;
}
function todayLocalIso() {
  const p = localParts(new Date().toISOString());
  return `${p.year}-${p.month}-${p.day}`;
}
function minutesFromTime(value) {
  if (!/^\d{2}:\d{2}$/.test(value || "")) return null;
  const [h,m] = value.split(":").map(Number);
  return h * 60 + m;
}
function timeFromMinutes(total) {
  total = ((Math.round(total) % 1440) + 1440) % 1440;
  return `${String(Math.floor(total / 60)).padStart(2,"0")}:${String(total % 60).padStart(2,"0")}`;
}
let editPunchMode = "full";
function setPunchEditorMode(mode) {
  editPunchMode = mode === "half" ? "half" : "full";
  const full = editPunchMode === "full";
  els.editFullDayBtn.classList.toggle("active", full);
  els.editHalfDayBtn.classList.toggle("active", !full);
  els.editPunchEntry2Label.classList.toggle("hidden", !full);
  els.editPunchExit2Label.classList.toggle("hidden", !full);
  els.editPunchExit1.required = true;
  els.editPunchEntry2.required = full;
  els.editPunchExit2.required = full;
  if (!full) {
    els.editPunchEntry2.value = "";
    els.editPunchExit2.value = "";
  }
  calculateSplitHours();
}
function calculateSplitHours() {
  const e1 = minutesFromTime(els.editPunchEntry1.value);
  const s1 = minutesFromTime(els.editPunchExit1.value);
  if (editPunchMode === "half") {
    if (e1 === null || s1 === null) { els.editPunchHours.value = ""; return; }
    if (!(e1 < s1)) { els.editPunchHours.value = "Horari no vàlid"; return; }
    const total = s1 - e1;
    els.editPunchHours.value = `${Math.floor(total/60)} h ${String(total%60).padStart(2,"0")} min`;
    return;
  }
  const e2 = minutesFromTime(els.editPunchEntry2.value);
  const s2 = minutesFromTime(els.editPunchExit2.value);
  if ([e1,s1,e2,s2].some(v => v === null)) { els.editPunchHours.value = ""; return; }
  if (!(e1 < s1 && s1 <= e2 && e2 < s2)) { els.editPunchHours.value = "Horari no vàlid"; return; }
  const total = (s1 - e1) + (s2 - e2);
  els.editPunchHours.value = `${Math.floor(total/60)} h ${String(total%60).padStart(2,"0")} min`;
}
async function loadPunchDay() {
  if (!assertPrimaryAdmin()) return;
  const employeeId = els.editPunchEmployee.value, date = els.editPunchDate.value;
  if (!employeeId || !date) return showResult(false, "Dades incompletes", "Selecciona treballador i data.");
  const { data, error } = await db.rpc("admin_obtenir_jornada_doble", { p_empleat_id: Number(employeeId), p_data: date });
  if (error) return showResult(false, "No s'ha pogut carregar", humanizeError(error.message));
  const row = Array.isArray(data) ? data[0] : data;
  const hasFirstShift = Boolean(row?.entrada_1 && row?.sortida_1);
  const hasSecondShift = Boolean(row?.entrada_2 && row?.sortida_2);
  setPunchEditorMode(hasSecondShift ? "full" : hasFirstShift ? "half" : editPunchMode);
  els.editPunchEntry1.value = row?.entrada_1 ? String(row.entrada_1).slice(0,5) : "";
  els.editPunchExit1.value = row?.sortida_1 ? String(row.sortida_1).slice(0,5) : "";
  els.editPunchEntry2.value = row?.entrada_2 ? String(row.entrada_2).slice(0,5) : "";
  els.editPunchExit2.value = row?.sortida_2 ? String(row.sortida_2).slice(0,5) : "";
  calculateSplitHours();
  showResult(true, "Jornada carregada", hasSecondShift ? "S'ha detectat una jornada completa amb pausa intermèdia." : row?.entrada_1 ? "S'ha detectat una mitja jornada (1 entrada i 1 sortida)." : "Aquest dia encara no té fitxatges.");
}
async function savePunchDay(event) {
  event.preventDefault();
  if (!assertPrimaryAdmin()) return;
  const employeeId = Number(els.editPunchEmployee.value);
  const date = els.editPunchDate.value;
  const e1 = els.editPunchEntry1.value;
  const s1 = els.editPunchExit1.value;
  const reason = els.editPunchReason.value.trim();
  if (!employeeId || !date || !e1 || !s1 || !reason) return showResult(false, "Dades incompletes", "Omple treballador, data, les hores i el motiu.");
  if (date > todayLocalIso()) return showResult(false, "Data no permesa", "No es poden crear jornades en dies futurs.");
  if (editPunchMode === "half" && !(minutesFromTime(e1) < minutesFromTime(s1))) return showResult(false, "Horari no vàlid", "A la mitja jornada, l'entrada ha de ser anterior a la sortida.");
  if (editPunchMode === "full") {
    const e2 = els.editPunchEntry2.value, s2 = els.editPunchExit2.value;
    if (!e2 || !s2) return showResult(false, "Dades incompletes", "A la jornada completa cal indicar les dues entrades i les dues sortides.");
    if (!(minutesFromTime(e1) < minutesFromTime(s1) && minutesFromTime(s1) <= minutesFromTime(e2) && minutesFromTime(e2) < minutesFromTime(s2))) return showResult(false, "Horari no vàlid", "Revisa l'ordre de les quatre hores.");
  }
  els.savePunchDayBtn.disabled = true;
  let error;
  if (editPunchMode === "half") {
    ({ error } = await db.rpc("admin_guardar_jornada", { p_empleat_id: employeeId, p_data: date, p_hora_entrada: e1, p_hora_sortida: s1, p_motiu: reason }));
  } else {
    ({ error } = await db.rpc("admin_guardar_jornada_doble", { p_empleat_id: employeeId, p_data: date, p_entrada_1: e1, p_sortida_1: s1, p_entrada_2: els.editPunchEntry2.value, p_sortida_2: els.editPunchExit2.value, p_motiu: reason }));
  }
  els.savePunchDayBtn.disabled = false;
  if (error) return showResult(false, "No s'ha pogut guardar", humanizeError(error.message));
  showResult(true, editPunchMode === "half" ? "Mitja jornada guardada" : "Jornada completa guardada", editPunchMode === "half" ? `${date} · ${e1}-${s1}` : `${date} · ${e1}-${s1} / ${els.editPunchEntry2.value}-${els.editPunchExit2.value}`);
  await loadRecords();
}
async function clearPunchDay() {
  if (!assertPrimaryAdmin()) return;
  const employeeId = Number(els.editPunchEmployee.value), date = els.editPunchDate.value, reason = els.editPunchReason.value.trim();
  if (!employeeId || !date || !reason) return showResult(false, "Dades incompletes", "Selecciona treballador, data i escriu el motiu.");
  if (!confirm("Vols deixar aquest dia sense cap fitxatge? L'acció quedarà registrada a l'auditoria.")) return;
  const { error } = await db.rpc("admin_esborrar_jornada", { p_empleat_id: employeeId, p_data: date, p_motiu: reason });
  if (error) return showResult(false, "No s'ha pogut corregir", humanizeError(error.message));
  showResult(true, "Jornada eliminada", "El canvi ha quedat registrat a l'auditoria.");
  [els.editPunchEntry1,els.editPunchExit1,els.editPunchEntry2,els.editPunchExit2,els.editPunchHours].forEach(el => el.value = "");
  await loadRecords();
}
function selectedWeekdays() { return [...els.weekdayPicker.querySelectorAll('input[type="checkbox"]:checked')].map(x => Number(x.value)); }
async function createBatchDays() {
  if (!assertPrimaryAdmin()) return;
  const allActive = els.batchAllActive.checked;
  const employeeId = Number(els.editPunchEmployee.value) || null;
  const start = els.batchStartDate.value, end = els.batchEndDate.value;
  const e1 = els.batchEntry1.value, s1 = els.batchExit1.value, e2 = els.batchEntry2.value, s2 = els.batchExit2.value;
  const reason = els.batchReason.value.trim(), weekdays = selectedWeekdays();
  if ((!allActive && !employeeId) || !start || !end || !e1 || !s1 || !e2 || !s2 || !reason || !weekdays.length) {
    return showResult(false, "Dades incompletes", "Selecciona un treballador o tots els actius, les dates, les quatre hores, el motiu i almenys un dia de la setmana.");
  }
  if (start > end || end > todayLocalIso()) return showResult(false, "Dates incorrectes", "El rang ha de ser vàlid i no pot incloure dies futurs.");
  const target = allActive ? "tots els empleats actius" : "el treballador seleccionat";
  if (!confirm(`Es crearan o reemplaçaran dues jornades diàries per a ${target}. Vols continuar?`)) return;
  els.createBatchDaysBtn.disabled = true;
  const { data, error } = await db.rpc("admin_guardar_jornades_massives_dobles", {
    p_empleat_id: employeeId, p_tots_actius: allActive, p_data_inici: start, p_data_fi: end,
    p_dies_setmana: weekdays, p_entrada_1: e1, p_sortida_1: s1, p_entrada_2: e2, p_sortida_2: s2, p_motiu: reason
  });
  els.createBatchDaysBtn.disabled = false;
  if (error) return showResult(false, "No s'ha pogut completar", humanizeError(error.message));
  const row = Array.isArray(data) ? data[0] : data;
  showResult(true, "Fitxatge massiu completat", `${row?.jornades_creades ?? 0} dies amb dues jornades guardats per a ${row?.empleats_processats ?? 0} empleats.`);
  await loadRecords();
}

async function loadAutoPunchConfig() {
  if (!assertPrimaryAdmin()) return;
  const { data, error } = await db.rpc("admin_obtenir_config_fitxatge_automatic_doble");
  if (error) { els.autoPunchStatus.textContent = "Error de configuració"; return; }
  const config = Array.isArray(data) ? data[0] : data;
  els.autoPunchEnabled.checked = Boolean(config?.actiu);
  els.autoPunchEntry1.value = String(config?.entrada_1 || "08:00").slice(0,5);
  els.autoPunchExit1.value = String(config?.sortida_1 || "13:00").slice(0,5);
  els.autoPunchEntry2.value = String(config?.entrada_2 || "15:00").slice(0,5);
  els.autoPunchExit2.value = String(config?.sortida_2 || "17:00").slice(0,5);
  updateAutoPunchStatus();
}
function updateAutoPunchStatus() {
  const enabled = els.autoPunchEnabled.checked;
  els.autoPunchStatus.textContent = enabled ? "Activat" : "Desactivat";
  els.autoPunchStatus.classList.toggle("active", enabled);
}
async function saveAutoPunchConfig() {
  if (!assertPrimaryAdmin()) return;
  const e1=els.autoPunchEntry1.value, s1=els.autoPunchExit1.value, e2=els.autoPunchEntry2.value, s2=els.autoPunchExit2.value;
  if (!e1 || !s1 || !e2 || !s2) return showResult(false, "Horari incomplet", "Indica les quatre hores de les dues jornades.");
  els.saveAutoPunchBtn.disabled = true;
  const { error } = await db.rpc("admin_guardar_config_fitxatge_automatic_doble", {
    p_actiu: els.autoPunchEnabled.checked, p_entrada_1:e1, p_sortida_1:s1, p_entrada_2:e2, p_sortida_2:s2
  });
  els.saveAutoPunchBtn.disabled = false;
  if (error) return showResult(false, "No s'ha pogut guardar", humanizeError(error.message));
  updateAutoPunchStatus();
  showResult(true, "Configuració guardada", els.autoPunchEnabled.checked
    ? `Automàtic activat: ${e1}-${s1} i ${e2}-${s2}, de dilluns a divendres.`
    : "Fitxatge automàtic desactivat. Els fitxatges es faran manualment.");
}




async function requestNotifications() {
  if (!("Notification" in window)) return showResult(false, "No compatible", "Aquest navegador no admet notificacions web.");
  const permission = await Notification.requestPermission();
  if (permission === "granted") {
    showResult(true, "Notificacions activades", "Rebràs avisos mentre l'aplicació estigui oberta o en segon pla.");
    notifyUser("PCM Fruits", "Notificacions activades correctament.");
  } else showResult(false, "Permís no concedit", "Activa les notificacions des dels ajustos del navegador.");
}
async function notifyUser(title, body) {
  if (!("Notification" in window) || Notification.permission !== "granted") return;
  try {
    const reg = await navigator.serviceWorker?.ready;
    if (reg) await reg.showNotification(title, { body, icon: "./assets/icon-192.png", badge: "./assets/icon-192.png", tag: "pcm-fitxatge", renotify: true });
    else new Notification(title, { body, icon: "./assets/icon-192.png" });
  } catch (_) {}
}
function setEditorMonth() {
  const now = new Date();
  els.editCalendarMonth.value = `${now.getFullYear()}-${String(now.getMonth()+1).padStart(2,"0")}`;
}
let editCalendarRequestId = 0;

async function renderEditPunchCalendar() {
  const requestId = ++editCalendarRequestId;
  const employeeId = els.editPunchEmployee.value;
  const monthValue = els.editCalendarMonth.value;
  if (!employeeId || !monthValue) {
    els.editPunchCalendar.innerHTML = '<span class="calendar-day empty"></span>';
    return;
  }

  const employee = employees.find(e => String(e.id) === String(employeeId));
  if (!employee) {
    els.editPunchCalendar.innerHTML = '<span class="calendar-day empty"></span>';
    return;
  }

  const [year, month] = monthValue.split("-").map(Number);
  let records = [];

  // IMPORTANT: no depenem de currentRecords (que està limitat als últims 10.000
  // fitxatges). L'editor ha de poder pintar també jornades històriques.
  const { data, error } = await db
    .from("vista_fitxatges")
    .select("data_hora,tipus")
    .eq("codi", employee.codi)
    .order("data_hora", { ascending: true });

  if (requestId !== editCalendarRequestId) return;

  if (!error) {
    records = (data || []).filter(r => {
      const p = localParts(r.data_hora);
      return `${p.year}-${p.month}` === monthValue;
    });
  } else {
    // Si la consulta directa falla, mantenim un fallback amb les dades ja carregades.
    records = currentRecords.filter(r => {
      const p = localParts(r.data_hora);
      return String(r.codi) === String(employee.codi) && `${p.year}-${p.month}` === monthValue;
    });
  }

  const worked = new Set(records.map(r => Number(localParts(r.data_hora).day)));
  const daysInMonth = new Date(year, month, 0).getDate();
  const mondayIndex = (new Date(year, month - 1, 1).getDay() + 6) % 7;
  const today = todayLocalIso();
  const cells=[];
  for(let i=0;i<mondayIndex;i++) cells.push('<button type="button" class="calendar-day empty" tabindex="-1"></button>');
  for(let day=1;day<=daysInMonth;day++){
    const iso=`${year}-${String(month).padStart(2,"0")}-${String(day).padStart(2,"0")}`;
    const classes=["calendar-day",worked.has(day)?"worked":"",els.editPunchDate.value===iso?"selected":"",iso>today?"future":""].filter(Boolean).join(" ");
    cells.push(`<button type="button" class="${classes}" data-editor-date="${iso}" ${iso>today?"disabled":""}><b>${day}</b>${worked.has(day)?"<small>Registrat</small>":""}</button>`);
  }
  els.editPunchCalendar.innerHTML=cells.join("");
}
async function selectEditorDate(date) {
  els.editPunchDate.value = date;
  els.editSelectedDate.textContent = date.split("-").reverse().join("/");
  renderEditPunchCalendar();
  await loadPunchDay();
}

function setWorkerPortalMonth() {
  const now = new Date();
  els.workerPortalMonth.value = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;
}

async function openWorkerPortal() {
  const code = els.workerPortalCode.value.trim();
  const month = els.workerPortalMonth.value;
  if (!code || !month) return showResult(false, "Dades incompletes", "Escriu el codi i selecciona el mes.");
  els.workerPortalBtn.disabled = true;
  try {
    const { data, error } = await db.rpc("portal_obtenir_registres", { p_codi: code, p_mes: `${month}-01` });
    if (error) throw error;
    const rows = data || [];
    const employeeName = rows[0]?.nom || "Treballador";
    const records = rows.filter(row => row.data_hora);
    els.workerPortalName.textContent = employeeName;
    const [year, monthNumber] = month.split("-").map(Number);
    els.workerPortalMonthLabel.textContent = new Intl.DateTimeFormat("ca-ES", { month: "long", year: "numeric" }).format(new Date(year, monthNumber - 1, 1));
    const daily = calculateDailyWork(records);
    const totalMs = daily.reduce((sum, day) => sum + day.totalMs, 0);
    els.workerPortalHours.textContent = formatDurationWords(totalMs);
    els.workerPortalDays.textContent = `${daily.length} ${daily.length === 1 ? "dia treballat" : "dies treballats"}`;
    renderWorkerPortalCalendar(year, monthNumber, daily);
    renderWorkerPortalRecords(records);
    els.workerPortalLogin.classList.add("hidden");
    els.workerPortalPanel.classList.remove("hidden");
    els.workerPortalCode.value = "";
  } catch (error) {
    showResult(false, "No s'ha pogut obrir el portal", humanizeError(error.message));
  } finally {
    els.workerPortalBtn.disabled = false;
  }
}

function renderWorkerPortalCalendar(year, month, daily) {
  const workedByDay = new Map(daily.map(item => [item.day, item]));
  const daysInMonth = new Date(year, month, 0).getDate();
  const mondayIndex = (new Date(year, month - 1, 1).getDay() + 6) % 7;
  const cells = [];
  for (let i = 0; i < mondayIndex; i++) cells.push('<span class="calendar-day empty" aria-hidden="true"></span>');
  for (let day = 1; day <= daysInMonth; day++) {
    const work = workedByDay.get(day);
    cells.push(`<span class="calendar-day${work ? " worked" : ""}"><b>${day}</b>${work ? `<small>${formatDurationCompact(work.totalMs)}</small>` : ""}</span>`);
  }
  els.workerPortalCalendar.innerHTML = cells.join("");
}

function renderWorkerPortalRecords(records) {
  if (!records.length) {
    els.workerPortalRecords.innerHTML = '<tr><td colspan="3" class="empty-row">No hi ha registres aquest mes.</td></tr>';
    return;
  }
  els.workerPortalRecords.innerHTML = records.slice().reverse().map(record => {
    const p = localParts(record.data_hora);
    return `<tr><td>${p.day}/${p.month}/${p.year}</td><td>${p.hour}:${p.minute}:${p.second}</td><td><span class="badge ${record.tipus === "entrada" ? "entry" : "exit"}">${escapeHtml(record.tipus)}</span></td></tr>`;
  }).join("");
}

function closeWorkerPortal() {
  els.workerPortalPanel.classList.add("hidden");
  els.workerPortalLogin.classList.remove("hidden");
  els.workerPortalRecords.innerHTML = "";
  els.workerPortalCalendar.innerHTML = "";
}

for (let d=1; d<=31; d++) els.dayFilter.insertAdjacentHTML("beforeend", `<option value="${d}">${d}</option>`);
setCurrentMonth();
els.entryBtn.addEventListener("click", () => registerPunch("entrada")); els.exitBtn.addEventListener("click", () => registerPunch("sortida")); els.adminLoginBtn.addEventListener("click", adminLogin); els.refreshBtn.addEventListener("click", loadAdminData); els.exportBtn.addEventListener("click", exportCsv); els.exportSummaryBtn.addEventListener("click", exportDailySummary); els.logoutBtn.addEventListener("click", logout); els.clearFiltersBtn.addEventListener("click", clearFilters);
[els.employeeSearch, els.employeeFilter, els.monthFilter, els.dayFilter, els.typeFilter].forEach(el => el.addEventListener("input", applyFilters));
document.querySelectorAll("[data-status]").forEach(btn => btn.addEventListener("click", () => { employeeStatus = btn.dataset.status; document.querySelectorAll("[data-status]").forEach(b => b.classList.toggle("active", b === btn)); renderEmployees(); }));
els.employeeForm.addEventListener("submit", saveEmployee);
els.cancelEditEmployeeBtn.addEventListener("click", resetEmployeeForm);
els.employeeListSearch.addEventListener("input", renderEmployees);
els.employeeSort.addEventListener("change", renderEmployees);
els.employeesBody.addEventListener("click", event => {
  const editButton = event.target.closest("[data-edit-employee]");
  const toggleButton = event.target.closest("[data-toggle-employee]");
  if (editButton) editEmployee(editButton.dataset.editEmployee);
  if (toggleButton) toggleEmployee(toggleButton.dataset.toggleEmployee);
});
els.employeeCode.addEventListener("keydown", e => { if (e.key === "Enter") registerPunch("entrada"); });
els.toggleCodeBtn?.addEventListener("click", () => {
  const show = els.employeeCode.type === "password";
  els.employeeCode.type = show ? "text" : "password";
  els.toggleCodeBtn.setAttribute("aria-pressed", String(show));
  els.toggleCodeBtn.textContent = show ? "🙈" : "👁";
  els.employeeCode.focus();
});
 els.adminPassword.addEventListener("keydown", e => { if (e.key === "Enter") adminLogin(); });
els.cancelBulkBtn.addEventListener("click", async () => { if (!activeBulkJobId) return; const { error } = await db.rpc("cancel_lar_fitxatge_grup_servidor", { p_job_id: activeBulkJobId }); if (error) showResult(false,"No s'ha pogut aturar",error.message); else els.bulkProgressText.textContent = "Cancel·lació sol·licitada…"; });
els.punchEditorForm.addEventListener("submit", savePunchDay);
els.loadPunchDayBtn.addEventListener("click", loadPunchDay);
els.clearPunchDayBtn.addEventListener("click", clearPunchDay);
els.createBatchDaysBtn.addEventListener("click", createBatchDays);
els.autoPunchEnabled.addEventListener("change", updateAutoPunchStatus);
els.saveAutoPunchBtn.addEventListener("click", saveAutoPunchConfig);
els.notificationBtn.addEventListener("click", requestNotifications);
els.editPunchEmployee.addEventListener("change", renderEditPunchCalendar);
els.editCalendarMonth.addEventListener("input", renderEditPunchCalendar);
els.editPunchCalendar.addEventListener("click", event => { const button = event.target.closest("[data-editor-date]"); if (button && !button.disabled) selectEditorDate(button.dataset.editorDate); });
els.editFullDayBtn.addEventListener("click", () => setPunchEditorMode("full"));
els.editHalfDayBtn.addEventListener("click", () => setPunchEditorMode("half"));
[els.editPunchEntry1,els.editPunchExit1,els.editPunchEntry2,els.editPunchExit2].forEach(el => el.addEventListener("input", calculateSplitHours));
setPunchEditorMode("full");
els.editPunchDate.max = todayLocalIso(); els.batchStartDate.max = todayLocalIso(); els.batchEndDate.max = todayLocalIso();

els.workerPortalBtn.addEventListener("click", openWorkerPortal);
els.workerPortalCloseBtn.addEventListener("click", closeWorkerPortal);
els.workerPortalCode.addEventListener("keydown", e => { if (e.key === "Enter") openWorkerPortal(); });
setWorkerPortalMonth();
setEditorMonth();
if (activeBulkJobId) monitorBulkJob(activeBulkJobId);
updateClock(); setInterval(updateClock, 1000); verifyConnection(); restoreSession();

if ('serviceWorker' in navigator && location.protocol !== 'file:') {
  window.addEventListener('load', () => navigator.serviceWorker.register('./service-worker.js').catch(console.warn));
}
