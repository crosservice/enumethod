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
const progressSection = document.getElementById("progress");
const stepBar = document.getElementById("step-bar");
const stepLabel = document.getElementById("step-label");
const statusBadge = document.getElementById("status-badge");
const logOutput = document.getElementById("log-output");

let autoScroll = true;

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

function setStatus(status) {
  statusBadge.textContent = status;
  statusBadge.className = "status-badge " + status;
  if (status !== "running") {
    startBtn.disabled = false;
    // Mark all completed on success
    if (status === "completed") {
      const segments = stepBar.children;
      for (let i = 0; i < 11; i++) {
        segments[i].className = "step completed";
      }
      stepLabel.textContent = "Complete";
    }
  }
}

form.addEventListener("submit", async (e) => {
  e.preventDefault();
  startBtn.disabled = true;
  logOutput.textContent = "";
  progressSection.classList.add("active");
  stepLabel.textContent = "Starting...";
  setStatus("running");
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
  appendLog(`Run #${run_id} started.\n`);

  // Open SSE stream
  const evtSource = new EventSource(`/api/runs/${run_id}/stream`);

  evtSource.addEventListener("catchup", (e) => {
    const data = JSON.parse(e.data);
    data.lines.forEach((line) => appendLog(line));
    updateSteps(data.step);
  });

  evtSource.addEventListener("output", (e) => {
    const data = JSON.parse(e.data);
    appendLog(data.line);
    updateSteps(data.step);
  });

  evtSource.addEventListener("status", (e) => {
    const data = JSON.parse(e.data);
    setStatus(data.status);
    updateSteps(data.step);
    evtSource.close();
  });

  evtSource.onerror = () => {
    evtSource.close();
    setStatus("failed");
  };
});
