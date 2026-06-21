const powerShellBlocks = document.querySelectorAll("pre code");
const buttons = document.querySelectorAll("[data-copy]");
const tokenPattern = /('(?:''|[^'])*')|("(?:`.|[^"])*")|(`)|(\$(?:true|false|null|[A-Za-z_][\w:]*)\b)|(-[A-Za-z][\w]*)|(\b(?:Install-Module|Import-Module|Publish-IntuneWin32App)\b)|(\b(?:Type|ProductCode|ScriptPath|EnforceSignatureCheck|RunAs32Bit|Path|FileOrFolderName|DetectionType|Check32BitOn64System|KeyPath|ValueName|Operator|DetectionValue|productCode|productVersionOperator|productVersion)\b(?=\s*=))|([@{}()[\],=])|(\b(?:CurrentUser|FileSystem|Registry|PowerShellScript|exists|version|greaterThanOrEqual|notConfigured)\b)/g;

const escapeHtml = (value) => value.replace(/[&<>"']/g, (character) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    "\"": "&quot;",
    "'": "&#39;"
})[character]);

const highlightPowerShell = (source) => {
    let highlighted = "";
    let lastIndex = 0;

    source.replace(tokenPattern, (match, singleQuotedString, doubleQuotedString, continuation, variable, parameter, command, property, punctuation, literal, offset) => {
        highlighted += escapeHtml(source.slice(lastIndex, offset));

        let tokenClass = "ps-literal";
        if (singleQuotedString || doubleQuotedString) {
            tokenClass = "ps-string";
        }
        else if (continuation) {
            tokenClass = "ps-continuation";
        }
        else if (variable) {
            tokenClass = "ps-variable";
        }
        else if (parameter) {
            tokenClass = "ps-parameter";
        }
        else if (command) {
            tokenClass = "ps-command";
        }
        else if (property) {
            tokenClass = "ps-property";
        }
        else if (punctuation) {
            tokenClass = "ps-punctuation";
        }

        highlighted += `<span class="${tokenClass}">${escapeHtml(match)}</span>`;
        lastIndex = offset + match.length;
        return match;
    });

    return highlighted + escapeHtml(source.slice(lastIndex));
};

powerShellBlocks.forEach((block) => {
    block.dataset.rawCode = block.textContent;
    block.innerHTML = highlightPowerShell(block.dataset.rawCode);
});

buttons.forEach((button) => {
    button.addEventListener("click", async () => {
        const target = document.getElementById(button.dataset.copy);
        if (!target) {
            return;
        }

        const originalLabel = button.getAttribute("aria-label");
        try {
            await navigator.clipboard.writeText(target.dataset.rawCode || target.innerText);
            button.setAttribute("aria-label", "Copied");
            button.style.background = "var(--mint)";
            window.setTimeout(() => {
                button.setAttribute("aria-label", originalLabel);
                button.style.background = "";
            }, 1200);
        }
        catch {
            button.setAttribute("aria-label", "Copy unavailable");
        }
    });
});