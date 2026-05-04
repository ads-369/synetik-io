const header = document.querySelector("[data-header]");
const revealItems = document.querySelectorAll(".reveal");
const leadForm = document.querySelector("[data-lead-form]");
const formStatus = document.querySelector("[data-form-status]");

const sessionId =
  window.crypto?.randomUUID?.() || `${Date.now()}-${Math.random().toString(16).slice(2)}`;

const syncHeader = () => {
  header?.classList.toggle("is-scrolled", window.scrollY > 24);
};

const track = (eventName, payload = {}) => {
  const body = {
    event: eventName,
    path: window.location.pathname,
    title: document.title,
    sessionId,
    timestamp: new Date().toISOString(),
    ...payload,
  };

  return fetch("/api/analytics", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
    keepalive: true,
  }).catch(() => undefined);
};

const revealObserver = new IntersectionObserver(
  (entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add("is-visible");
        revealObserver.unobserve(entry.target);
      }
    });
  },
  { threshold: 0.16 }
);

revealItems.forEach((item) => revealObserver.observe(item));
window.addEventListener("scroll", syncHeader, { passive: true });
syncHeader();

document.querySelectorAll("a[href^='#'], .button").forEach((element) => {
  element.addEventListener("click", () => {
    track("click", {
      label: element.textContent.trim(),
      href: element.getAttribute("href") || null,
    });
  });
});

leadForm?.addEventListener("submit", async (event) => {
  event.preventDefault();
  const formData = new FormData(leadForm);
  const payload = Object.fromEntries(formData.entries());

  formStatus.textContent = "Enviando contato...";

  try {
    const response = await fetch("/api/leads", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ ...payload, sessionId }),
    });

    if (!response.ok) {
      throw new Error("Lead endpoint failed");
    }

    leadForm.reset();
    formStatus.textContent = "Contato registrado. Proximo passo: diagnostico tecnico.";
    track("lead_submitted", { interest: payload.interest });
  } catch {
    formStatus.textContent = "Nao foi possivel registrar agora. Verifique se o servidor esta ativo.";
  }
});

track("page_view", {
  referrer: document.referrer || null,
  viewport: `${window.innerWidth}x${window.innerHeight}`,
});
