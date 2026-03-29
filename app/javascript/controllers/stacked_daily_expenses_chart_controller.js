import { Controller } from "@hotwired/stimulus";
import * as d3 from "d3";

const parseLocalDate = d3.timeParse("%Y-%m-%d");

/** Stacked bar chart: expenses per calendar day, category colors (root category). */
export default class extends Controller {
  static values = {
    data: Object,
  };

  connect() {
    this._resizeObserver = null;
    this._draw();
    this._resizeObserver = new ResizeObserver(() => {
      this._teardownSvg();
      this._draw();
    });
    this._resizeObserver.observe(this.element);
  }

  disconnect() {
    this._resizeObserver?.disconnect();
    this._teardownSvg();
  }

  _teardownSvg() {
    this.element.querySelectorAll("svg, div[data-tooltip]").forEach((el) => el.remove());
    this.element.style.position = "";
  }

  _draw() {
    const raw = this.dataValue || {};
    const dates = raw.dates || [];
    const layers = raw.layers || [];
    const currency = raw.currency || "USD";

    if (!dates.length || !layers.length) {
      return;
    }

    // Floor width so SVG + subpixel layout never exceeds the card (horizontal overflow).
    const w = Math.max(0, Math.floor(this.element.getBoundingClientRect().width));
    const h = Math.max(220, this.element.clientHeight || 280);
    const margin = { top: 12, right: 20, bottom: dates.length > 31 ? 52 : 36, left: 72 };

    if (w < margin.left + margin.right + 40) {
      return;
    }

    const innerW = w - margin.left - margin.right;
    const innerH = h - margin.top - margin.bottom;

    const totals = dates.map((_, i) => layers.reduce((s, l) => s + (Number(l.amounts[i]) || 0), 0));
    const maxY = d3.max(totals) || 0;
    if (maxY <= 0) {
      return;
    }

    const x = d3.scaleBand().domain(dates).range([0, innerW]).padding(0.25);

    const y = d3
      .scaleLinear()
      .domain([0, maxY * 1.05])
      .nice()
      .range([innerH, 0]);

    const docLang = document.documentElement.lang || undefined;
    const fmtMoney = new Intl.NumberFormat(docLang, {
      style: "currency",
      currency,
      maximumFractionDigits: 0,
      currencyDisplay: "narrowSymbol",
    });

    this.element.style.position = "relative";

    const svg = d3
      .select(this.element)
      .append("svg")
      .attr("viewBox", `0 0 ${w} ${h}`)
      .attr("width", "100%")
      .attr("height", h)
      .attr("role", "img")
      .attr("aria-label", "Daily expenses by category")
      .attr("preserveAspectRatio", "xMinYMin meet")
      .style("display", "block")
      .style("max-width", "100%")
      .style("overflow", "hidden");

    const g = svg.append("g").attr("transform", `translate(${margin.left},${margin.top})`);

    const xAxis = d3.axisBottom(x).tickFormat((d) => {
      const dt = parseLocalDate(d);
      return dt ? d3.timeFormat(dates.length > 60 ? "%b" : "%-d")(dt) : d;
    });

    if (dates.length > 45) {
      xAxis.tickValues(x.domain().filter((_, i) => i % Math.ceil(dates.length / 12) === 0));
    } else if (dates.length > 18) {
      xAxis.tickValues(x.domain().filter((_, i) => i % 2 === 0));
    }

    g.append("g")
      .attr("transform", `translate(0,${innerH})`)
      .call(xAxis)
      .selectAll("text")
      .attr("transform", "rotate(-35)")
      .style("text-anchor", "end")
      .attr("class", "text-xs fill-secondary");

    g.append("g")
      .call(
        d3
          .axisLeft(y)
          .ticks(4)
          .tickFormat((v) => fmtMoney.format(v)),
      )
      .selectAll("text")
      .attr("class", "text-xs fill-secondary");

    g.selectAll(".domain, .tick line").attr("class", "stroke-secondary opacity-40");

    const tooltip = d3
      .select(this.element)
      .append("div")
      .attr("data-tooltip", "")
      .style("position", "absolute")
      .style("pointer-events", "none")
      .style("opacity", 0)
      .style("background", "var(--color-container, #fff)")
      .style("border", "1px solid var(--color-border-primary, #e5e7eb)")
      .style("border-radius", "8px")
      .style("padding", "8px 10px")
      .style("font-size", "12px")
      .style("box-shadow", "0 2px 8px rgba(0,0,0,0.08)")
      .style("z-index", "20");

    const elBox = () => this.element.getBoundingClientRect();

    const showTip = (event, dayIndex) => {
      const dateStr = dates[dayIndex];
      const parts = layers
        .map((l) => ({
          key: l.key,
          name: l.name,
          color: l.color,
          v: Number(l.amounts[dayIndex]) || 0,
        }))
        .filter((p) => p.v > 0)
        .sort((a, b) => b.v - a.v);
      const total = parts.reduce((s, p) => s + p.v, 0);
      const lines = [`<div class="font-medium text-primary">${dateStr}</div>`];
      for (const p of parts) {
        lines.push(
          `<div class="flex justify-between gap-4"><span style="color:${p.color}">●</span> <span>${p.name}</span> <span class="tabular-nums">${fmtMoney.format(p.v)}</span></div>`,
        );
      }
      lines.push(
        `<div class="mt-1 pt-1 border-t border-primary font-medium text-primary">${fmtMoney.format(total)}</div>`,
      );
      tooltip.html(lines.join(""));
      tooltip.style("opacity", 1);
      const rect = elBox();
      tooltip.style("left", `${event.clientX - rect.left + 12}px`).style("top", `${event.clientY - rect.top + 12}px`);
    };

    dates.forEach((dateStr, dayIndex) => {
      let yBottom = 0;
      const barX = x(dateStr);
      const bw = x.bandwidth();
      if (barX === undefined) {
        return;
      }

      for (const layer of layers) {
        const v = Number(layer.amounts[dayIndex]) || 0;
        if (v <= 0) {
          continue;
        }
        const yTop = yBottom + v;
        const rectY = y(yTop);
        const rectH = Math.max(0, y(yBottom) - y(yTop));
        g.append("rect")
          .attr("x", barX)
          .attr("y", rectY)
          .attr("width", bw)
          .attr("height", rectH)
          .attr("fill", layer.color || "#64748b")
          .style("cursor", "pointer")
          .on("mouseenter", (event) => showTip(event, dayIndex))
          .on("mousemove", (event) => {
            const rect = elBox();
            tooltip.style("left", `${event.clientX - rect.left + 12}px`).style("top", `${event.clientY - rect.top + 12}px`);
          })
          .on("mouseleave", () => {
            tooltip.style("opacity", 0);
          });
        yBottom = yTop;
      }
    });
  }
}
