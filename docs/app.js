window.hljs?.highlightAll();

const copyStatus = document.getElementById("copy-status");

document.querySelectorAll("[data-copy]").forEach((button) => {
    const label = button.querySelector("span");
    const icon = button.querySelector("use");

    button.addEventListener("click", async () => {
        const target = document.getElementById(button.dataset.copy);
        if (!target) {
            return;
        }

        try {
            await navigator.clipboard.writeText(target.innerText);
            label.textContent = "Copied";
            icon.setAttribute("href", "#i-check");
            button.classList.add("is-copied");
            copyStatus.textContent = "Copied to clipboard";
            window.setTimeout(() => {
                label.textContent = "Copy";
                icon.setAttribute("href", "#i-copy");
                button.classList.remove("is-copied");
                copyStatus.textContent = "";
            }, 1600);
        }
        catch {
            label.textContent = "Copy failed";
            copyStatus.textContent = "Copy failed. Select the code and copy it manually.";
        }
    });
});

document.querySelectorAll("[data-tabs]").forEach((group) => {
    const tabs = [...group.querySelectorAll('[role="tab"]')];

    const select = (tab, focus = false) => {
        tabs.forEach((other) => {
            const selected = other === tab;
            other.setAttribute("aria-selected", String(selected));
            other.tabIndex = selected ? 0 : -1;
            document.getElementById(other.getAttribute("aria-controls")).hidden = !selected;
        });
        if (focus) {
            tab.focus();
        }
    };

    tabs.forEach((tab, index) => {
        tab.addEventListener("click", () => select(tab));
        tab.addEventListener("keydown", (event) => {
            const step = { ArrowRight: 1, ArrowLeft: -1 }[event.key];
            const jump = { Home: 0, End: tabs.length - 1 }[event.key];
            if (step === undefined && jump === undefined) {
                return;
            }
            event.preventDefault();
            select(tabs[jump ?? (index + step + tabs.length) % tabs.length], true);
        });
    });

    select(tabs[0]);
    group.classList.add("is-ready");
});
