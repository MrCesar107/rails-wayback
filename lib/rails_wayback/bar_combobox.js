(function (root, factory) {
  const Combobox = factory();

  if (typeof module !== "undefined" && module.exports) module.exports = Combobox;
  if (root) root.RailsWaybackCombobox = Combobox;
})(typeof globalThis !== "undefined" ? globalThis : this, function () {
  class RailsWaybackCombobox {
    constructor(element, options) {
      this.element = element;
      this.document = options.document;
      this.kind = options.kind;
      this.noun = options.noun;
      this.searchItems = options.searchItems;
      this.valueOf = options.valueOf;
      this.labelOf = options.labelOf;
      this.onOpen = options.onOpen || function () {};
      this.onSelect = options.onSelect || function () {};
      this.emptyLabel = options.emptyLabel;
      this.items = [];
      this.selectedValue = options.selectedValue || "";
      this.activeIndex = -1;

      this.trigger = element.querySelector("[data-rw-trigger]");
      this.valueElement = element.querySelector("[data-rw-value]");
      this.dropdown = element.querySelector("[data-rw-dropdown]");
      this.search = element.querySelector("[data-rw-search]");
      this.options = element.querySelector("[data-rw-options]");
      this.results = element.querySelector("[data-rw-results]");
    }

    get value() {
      return this.selectedValue;
    }

    connect(signal) {
      const listenerOptions = { signal: signal };
      this.trigger.addEventListener("click", () => this.toggle(), listenerOptions);
      this.trigger.addEventListener("keydown", (event) => this.handleTriggerKeydown(event), listenerOptions);
      this.search.addEventListener("input", (event) => this.render(event.target.value), listenerOptions);
      this.search.addEventListener("keydown", (event) => this.handleSearchKeydown(event), listenerOptions);
      this.options.addEventListener("click", (event) => this.handleOptionsClick(event), listenerOptions);
      this.document.addEventListener("click", (event) => {
        if (!this.element.contains(event.target)) this.close(false);
      }, listenerOptions);
    }

    toggle() {
      if (this.trigger.disabled) return;
      if (this.dropdown.hidden) {
        this.open();
      } else {
        this.close(true);
      }
    }

    open() {
      if (this.trigger.disabled) return;
      this.onOpen();
      this.dropdown.hidden = false;
      this.trigger.setAttribute("aria-expanded", "true");
      this.search.setAttribute("aria-expanded", "true");
      this.search.focus();
    }

    close(restoreFocus) {
      this.dropdown.hidden = true;
      this.trigger.setAttribute("aria-expanded", "false");
      this.search.setAttribute("aria-expanded", "false");
      this.search.removeAttribute("aria-activedescendant");
      if (restoreFocus) this.trigger.focus();
    }

    handleTriggerKeydown(event) {
      if (["ArrowDown", "ArrowUp", "Enter", " "].indexOf(event.key) === -1) return;

      event.preventDefault();
      this.open();
      if (event.key === "ArrowUp") this.moveActiveOption(-1);
    }

    handleSearchKeydown(event) {
      if (event.key === "Escape") {
        event.preventDefault();
        this.close(true);
      } else if (event.key === "ArrowDown") {
        event.preventDefault();
        this.moveActiveOption(1);
      } else if (event.key === "ArrowUp") {
        event.preventDefault();
        this.moveActiveOption(-1);
      } else if (event.key === "Enter") {
        const option = this.options.children[this.activeIndex];
        if (!option) return;

        event.preventDefault();
        this.select(option.dataset.rwOptionValue);
      }
    }

    handleOptionsClick(event) {
      let target = event.target;
      while (target && target !== this.options) {
        if (target.dataset && target.dataset.rwOptionValue) {
          this.select(target.dataset.rwOptionValue);
          return;
        }
        target = target.parentNode;
      }
    }

    moveActiveOption(amount) {
      const count = this.options.children.length;
      if (count === 0) return;

      const next = this.activeIndex < 0
        ? (amount > 0 ? 0 : count - 1)
        : (this.activeIndex + amount + count) % count;
      this.setActiveOption(next);
    }

    setActiveOption(index) {
      this.activeIndex = index;
      Array.from(this.options.children).forEach(function (option, optionIndex) {
        if (optionIndex === index) {
          option.classList.add("rw-active-option");
        } else {
          option.classList.remove("rw-active-option");
        }
      });

      const active = this.options.children[index];
      if (!active) {
        this.search.removeAttribute("aria-activedescendant");
        return;
      }

      this.search.setAttribute("aria-activedescendant", active.id);
      if (typeof active.scrollIntoView === "function") {
        active.scrollIntoView({ block: "nearest" });
      }
    }

    select(value) {
      if (!this.items.some((item) => this.valueOf(item) === value)) return;

      const changed = value !== this.selectedValue;
      this.selectedValue = value;
      this.search.value = "";
      this.render("");
      this.close(true);
      this.onSelect(value, changed);
    }

    setItems(items, selectedValue) {
      this.items = Array.isArray(items) ? items : [];
      const requestedValue = selectedValue === undefined ? this.selectedValue : selectedValue;
      const selected = this.items.find((item) => this.valueOf(item) === requestedValue);
      this.selectedValue = selected
        ? this.valueOf(selected)
        : (this.items[0] ? this.valueOf(this.items[0]) : "");
      this.search.value = "";
      this.setDisabled(this.items.length === 0);
      this.render("");
      return this.selectedValue;
    }

    setLoading(valueLabel, resultLabel) {
      this.close(false);
      this.items = [];
      this.selectedValue = "";
      this.options.innerHTML = "";
      this.setDisabled(true);
      this.valueElement.textContent = valueLabel;
      this.results.textContent = resultLabel;
    }

    setUnavailable(label) {
      this.setLoading(label, label);
    }

    setDisabled(disabled) {
      this.search.disabled = disabled;
      this.trigger.disabled = disabled;
    }

    render(query) {
      const result = this.searchItems(this.items, query, this.selectedValue);
      this.options.innerHTML = "";
      result.visible.forEach((item, index) => {
        this.options.appendChild(this.buildOption(item, index));
      });

      if (!this.items.some((item) => this.valueOf(item) === this.selectedValue) &&
          result.visible.length > 0) {
        this.selectedValue = this.valueOf(result.visible[0]);
      }

      const selectedIndex = result.visible.findIndex((item) => (
        this.valueOf(item) === this.selectedValue
      ));
      this.setActiveOption(selectedIndex >= 0 ? selectedIndex : (result.visible.length ? 0 : -1));

      const selected = this.items.find((item) => this.valueOf(item) === this.selectedValue);
      this.valueElement.textContent = selected ? this.labelOf(selected) : this.emptyLabel;
      const retained = result.visible.length > result.matches.length;
      this.results.textContent = this.resultMessage(result.matches.length, query, retained);
      this.search.setAttribute(
        "aria-invalid",
        result.matches.length === 0 && query.trim() ? "true" : "false"
      );
    }

    buildOption(item, index) {
      const value = this.valueOf(item);
      const label = this.labelOf(item);
      const option = this.document.createElement("button");
      option.type = "button";
      option.className = "rw-combobox-option";
      option.id = "rails-wayback-" + this.kind + "-option-" + index;
      option.dataset.rwOptionValue = value;
      option.textContent = label;
      option.tabIndex = -1;
      option.setAttribute("role", "option");
      option.setAttribute("aria-selected", value === this.selectedValue ? "true" : "false");
      option.title = label;
      return option;
    }

    resultMessage(count, query, selectionRetained) {
      if (!query.trim()) return count + " " + this.noun + (count === 1 ? "" : "s") + " loaded";
      if (count > 0) return count + " matching " + this.noun + (count === 1 ? "" : "s");
      return "No matching " + this.noun + "s" +
        (selectionRetained ? "; current selection retained" : "");
    }
  }

  return RailsWaybackCombobox;
});
