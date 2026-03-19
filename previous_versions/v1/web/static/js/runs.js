async function loadRuns() {
  const tbody = document.getElementById("runs-body");
  const empty = document.getElementById("empty");

  let runs;
  try {
    const res = await fetch("/api/runs");
    runs = await res.json();
  } catch {
    tbody.innerHTML = '<tr><td colspan="8" style="color:var(--red)">Failed to load runs</td></tr>';
    return;
  }

  if (runs.length === 0) {
    empty.style.display = "block";
    return;
  }

  empty.style.display = "none";
  tbody.innerHTML = runs
    .map((r) => {
      const actions = [];
      if (r.status === "completed") {
        actions.push(`<a href="/report/${r.id}">View Report</a>`);
        actions.push(`<a href="/api/runs/${r.id}/export">Export ZIP</a>`);
      }
      if (r.status === "running") {
        actions.push(`<a href="/">Watch Live</a>`);
      }
      return `<tr>
        <td>${r.id}</td>
        <td>${r.target_ip}</td>
        <td>${r.domain || "—"}</td>
        <td><span class="badge ${r.status}">${r.status}</span></td>
        <td>${r.current_step}/11</td>
        <td>${r.started_at || "—"}</td>
        <td>${r.finished_at || "—"}</td>
        <td>${actions.join(" | ") || "—"}</td>
      </tr>`;
    })
    .join("");
}

loadRuns();
