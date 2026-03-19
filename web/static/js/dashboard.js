const STEP_NAMES = {
  1: "Passive Intelligence Gathering",
  2: "Port Scanning",
  3: "Web Service Enumeration",
  4: "SMB / NetBIOS",
  5: "SNMP Enumeration",
  6: "Mail Services",
  7: "Database Services",
  8: "Authentication Testing",
  9: "Vulnerability Scanning",
  10: "Traffic & Protocol Analysis",
  11: "Consolidation & Reporting",
};

const form = document.getElementById("scan-form");
const startBtn = document.getElementById("start-btn");
const cancelBtn = document.getElementById("cancel-btn");
const progressSection = document.getElementById("progress");
const stepBar = document.getElementById("step-bar");
const stepLabel = document.getElementById("step-label");
const statusBadge = document.getElementById("status-badge");
const logOutput = document.getElementById("log-output");
const detailBar = document.getElementById("detail-bar");
const subProgress = document.getElementById("sub-progress");
const subProgressFill = document.getElementById("sub-progress-fill");

let autoScroll = true;
let currentRunId = null;
let evtSource = null;

logOutput.addEventListener("scroll", () => {
  const gap = logOutput.scrollHeight - logOutput.scrollTop - logOutput.clientHeight;
  autoScroll = gap < 40;
});

function appendLog(text) {
  logOutput.textContent += text + "\n";
  if (autoScroll) {
    logOutput.scrollTop = logOutput.scrollHeight;
  }
}

function updateSteps(step) {
  const segments = stepBar.children;
  for (let i = 0; i < 11; i++) {
    segments[i].className = "step";
    if (i + 1 < step) {
      segments[i].classList.add("completed");
    } else if (i + 1 === step) {
      segments[i].classList.add("active-step");
    }
  }
  if (step > 0 && step <= 11) {
    stepLabel.textContent = `Step ${step}/11: ${STEP_NAMES[step]}`;
  }
}

function updateDetail(detail, progress) {
  if (detail) {
    detailBar.textContent = detail;
  }
  if (progress && progress[1] > 0) {
    subProgress.style.display = "block";
    const pct = Math.min(100, Math.round((progress[0] / progress[1]) * 100));
    subProgressFill.style.width = pct + "%";
    detailBar.textContent = `${detail}  (${pct}%)`;
  } else {
    subProgress.style.display = "none";
    subProgressFill.style.width = "0%";
  }
}

function setStatus(status) {
  statusBadge.textContent = status;
  statusBadge.className = "status-badge " + status;
  if (status !== "running") {
    startBtn.disabled = false;
    cancelBtn.style.display = "none";
    subProgress.style.display = "none";
    detailBar.textContent = "";
    if (status === "completed") {
      const segments = stepBar.children;
      for (let i = 0; i < 11; i++) {
        segments[i].className = "step completed";
      }
      stepLabel.textContent = "Complete";
    } else if (status === "cancelled") {
      stepLabel.textContent = "Cancelled";
    }
    currentRunId = null;
  }
}

async function cancelRun() {
  if (!currentRunId) return;
  cancelBtn.disabled = true;
  cancelBtn.textContent = "Cancelling...";
  try {
    await fetch(`/api/runs/${currentRunId}/cancel`, { method: "POST" });
  } catch (err) {
    // SSE status event will handle UI update
  }
}

form.addEventListener("submit", async (e) => {
  e.preventDefault();
  startBtn.disabled = true;
  logOutput.textContent = "";
  detailBar.textContent = "";
  subProgress.style.display = "none";
  subProgressFill.style.width = "0%";
  progressSection.classList.add("active");
  stepLabel.textContent = "Starting...";
  setStatus("running");
  cancelBtn.style.display = "inline-block";
  cancelBtn.disabled = false;
  cancelBtn.textContent = "Cancel";
  updateSteps(0);

  const body = {
    target_ip: document.getElementById("target_ip").value,
    domain: document.getElementById("domain").value,
    steps: document.getElementById("steps").value,
    timing: document.getElementById("timing").value,
    skip_udp: document.getElementById("skip_udp").checked,
    skip_bruteforce: document.getElementById("skip_bruteforce").checked,
    dry_run: document.getElementById("dry_run").checked,
    wordlist: document.getElementById("wordlist").value,
  };

  let res;
  try {
    res = await fetch("/api/runs", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
  } catch (err) {
    appendLog("ERROR: " + err.message);
    setStatus("failed");
    return;
  }

  if (!res.ok) {
    const data = await res.json();
    appendLog("ERROR: " + (data.error || "Unknown error"));
    setStatus("failed");
    return;
  }

  const { run_id } = await res.json();
  currentRunId = run_id;
  appendLog(`Run #${run_id} started.\n`);

  // Open SSE stream
  evtSource = new EventSource(`/api/runs/${run_id}/stream`);

  evtSource.addEventListener("catchup", (e) => {
    const data = JSON.parse(e.data);
    data.lines.forEach((line) => appendLog(line));
    updateSteps(data.step);
    updateDetail(data.detail || "", data.progress);
  });

  evtSource.addEventListener("output", (e) => {
    const data = JSON.parse(e.data);
    appendLog(data.line);
    updateSteps(data.step);
    updateDetail(data.detail || "", data.progress);
  });

  evtSource.addEventListener("status", (e) => {
    const data = JSON.parse(e.data);
    setStatus(data.status);
    updateSteps(data.step);
    evtSource.close();
    evtSource = null;
  });

  evtSource.onerror = () => {
    evtSource.close();
    evtSource = null;
    setStatus("failed");
  };
});
