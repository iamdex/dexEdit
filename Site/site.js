/* -----------------------------------------------------------------------------
   Two jobs, and neither of them rewrites any text.

   1. The raw switch adds a class. That is all it does: the characters on this
      page are the same in both states, which is the claim the page is making.
   2. The waitlist. WAITLIST_ENDPOINT takes a POST from any form service —
      Formspree, Buttondown, Tally, your own. Left empty, the form falls back to
      opening a pre-addressed mail, so the page is never a dead end.
----------------------------------------------------------------------------- */

const WAITLIST_ENDPOINT = "";
const WAITLIST_MAILTO = "hellodave@espertini.com";

const body = document.body;
const toggle = document.getElementById("toggle");
const toggleLabel = document.getElementById("toggle-label");

/* Every word the script can put on screen comes from the markup, so this file
   is the same in both languages and neither can drift from the other. */
function setRaw(on) {
  body.classList.toggle("raw", on);
  toggle.setAttribute("aria-pressed", String(on));
  toggleLabel.textContent = on ? toggle.dataset.styled : toggle.dataset.raw;
}

toggle.addEventListener("click", () => setRaw(!body.classList.contains("raw")));

document.addEventListener("keydown", (event) => {
  // Not while someone is typing their address into the form.
  const typing = event.target instanceof HTMLInputElement;
  if (typing || event.metaKey || event.ctrlKey || event.altKey) return;
  if (event.key === "r" || event.key === "R") setRaw(!body.classList.contains("raw"));
});

for (const form of document.querySelectorAll(".signup")) {
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    const email = new FormData(form).get("email");

    if (!WAITLIST_ENDPOINT) {
      window.location.href =
        `mailto:${WAITLIST_MAILTO}?subject=${encodeURIComponent(form.dataset.subject)}` +
        `&body=${encodeURIComponent(`${form.dataset.mailBody}\n\n${email}\n`)}`;
      return;
    }

    const button = form.querySelector("button");
    button.disabled = true;

    try {
      await fetch(WAITLIST_ENDPOINT, {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json" },
        body: JSON.stringify({ email }),
      });
      form.hidden = true;
      document.getElementById("fine")?.setAttribute("hidden", "");
      document.getElementById("said")?.removeAttribute("hidden");
    } catch {
      button.disabled = false;
      button.textContent = form.dataset.failed;
    }
  });
}
