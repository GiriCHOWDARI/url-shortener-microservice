document.getElementById("shortenBtn").addEventListener("click", async () => {
    const original = document.getElementById("originalUrl").value.trim();
    const alias = document.getElementById("alias").value.trim();
    const expiry = document.getElementById("expiry").value.trim();
    if (!original) return alert("Please enter a URL");
    let apiUrl = `/api/shorten?original_url=${encodeURIComponent(original)}`;
    if (alias) apiUrl += `&custom_alias=${encodeURIComponent(alias)}`;
    if (expiry) apiUrl += `&expires_days=${encodeURIComponent(expiry)}`;
    try {
        const token = localStorage.getItem("token") || "";
        const res = await fetch(apiUrl, {
            method: "POST",
            headers: { "Authorization": `Bearer ${token}` }
        });
        if (!res.ok) {
            const err = await res.json();
            throw new Error(err.detail || "Failed");
        }
        const data = await res.json();
        const div = document.getElementById("result");
        div.classList.remove("hidden");
        div.innerHTML = `<a href="${data.short_url}" target="_blank">${data.short_url}</a><button class="copy-btn" onclick="copyToClipboard('${data.short_url}')">Copy</button>`;
    } catch (e) {
        alert(`Error: ${e.message}`);
    }
});

function copyToClipboard(text) {
    navigator.clipboard.writeText(text).then(() => alert("Copied!"))
        .catch(() => prompt("Copy manually:", text));
}
