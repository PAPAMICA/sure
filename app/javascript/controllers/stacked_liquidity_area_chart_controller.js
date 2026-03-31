import { Controller } from "@hotwired/stimulus";
import * as d3 from "d3";

const parseLocalDate = d3.timeParse("%Y-%m-%d");

// Stacked area chart for liquidity by account over time.
export default class extends Controller {
  static values = { data: Object };

  connect() {
    this._resizeObserver = new ResizeObserver(() => {
      this._teardown();
      this._draw();
    });
    this._draw();
    this._resizeObserver.observe(this.element);
  }

  disconnect() {
    this._resizeObserver?.disconnect();
    this._teardown();
  }

  _teardown() {
    this.element.querySelectorAll("svg, div[data-tooltip]").forEach((el) => el.remove());
    this.element.style.position = "";
  }

  _draw() {
    const raw = this.dataValue || {};
    const dates = raw.dates || [];
    const layers = raw.layers || [];
    if (!dates.length || !layers.length) return;

    const width = Math.max(0, Math.floor(this.element.getBoundingClientRect().width));
    const height = Math.max(250, this.element.clientHeight || 280);
    const margin = { top: 12, right: 20, bottom: 34, left: 72 };
    if (width < margin.left + margin.right + 40) return;

    const innerW = width - margin.left - margin.right;
    const innerH = height - margin.top - margin.bottom;
    const parsedDates = dates.map((d) => parseLocalDate(d));

    const rows = parsedDates.map((date, i) => {
      const row = { date, dateLabel: dates[i] };
      layers.forEach((layer) => {
        row[layer.key] = Number(layer.amounts[i]) || 0;
      });
      return row;
    });

    const keys = layers.map((l) => l.key);
    const stacked = d3.stack().keys(keys)(rows);
    const yMax = d3.max(stacked, (serie) => d3.max(serie, (d) => d[1])) || 0;
    if (yMax <= 0) return;

    const x = d3.scaleTime().domain(d3.extent(parsedDates)).range([0, innerW]);
    const y = d3.scaleLinear().domain([0, yMax * 1.05]).nice().range([innerH, 0]);

    const docLang = document.documentElement.lang || undefined;
    const moneyFmt = new Intl.NumberFormat(docLang, {
      style: "currency",
      currency: raw.currency || "EUR",
      maximumFractionDigits: 0,
      currencyDisplay: "narrowSymbol",
    });

    this.element.style.position = "relative";
    const svg = d3
      .select(this.element)
      .append("svg")
      .attr("viewBox", `0 0 ${width} ${height}`)
      .attr("width", "100%")
      .attr("height", height)
      .style("display", "block")
      .style("max-width", "100%");

    const g = svg.append("g").attr("transform", `translate(${margin.left},${margin.top})`);

    g.append("g")
      .attr("transform", `translate(0,${innerH})`)
      .call(
        d3.axisBottom(x).ticks(6).tickFormat((d) => {
          const dt = d instanceof Date ? d : new Date(d);
          return d3.timeFormat("%d %b")(dt);
        })
      )
      .selectAll("text")
      .attr("class", "text-xs fill-secondary");

    g.append("g")
      .call(d3.axisLeft(y).ticks(4).tickFormat((v) => moneyFmt.format(v)))
      .selectAll("text")
      .attr("class", "text-xs fill-secondary");

    g.selectAll(".domain, .tick line").attr("class", "stroke-secondary opacity-40");

    const area = d3
      .area()
      .x((d) => x(d.data.date))
      .y0((d) => y(d[0]))
      .y1((d) => y(d[1]))
      .curve(d3.curveMonotoneX);

    stacked.forEach((serie, idx) => {
      g.append("path")
        .datum(serie)
        .attr("fill", layers[idx].color)
        .attr("fill-opacity", 0.35)
        .attr("stroke", layers[idx].color)
        .attr("stroke-width", 1.5)
        .attr("d", area);
    });

    const tooltip = d3
      .select(this.element)
      .append("div")
      .attr("data-tooltip", "")
      .attr(
        "class",
        "absolute pointer-events-none z-20 max-w-[min(22rem,calc(100vw-2rem))] rounded-lg border border-primary bg-container px-3 py-2 text-xs text-primary shadow-border-xs"
      )
      .style("opacity", 0);

    const bisectDate = d3.bisector((d) => d.date).left;
    const elBox = () => this.element.getBoundingClientRect();

    g.append("rect")
      .attr("width", innerW)
      .attr("height", innerH)
      .attr("fill", "none")
      .attr("pointer-events", "all")
      .on("mousemove", (event) => {
        const [mx] = d3.pointer(event);
        const date = x.invert(mx);
        const i = Math.min(rows.length - 1, Math.max(0, bisectDate(rows, date)));
        const row = rows[i];
        if (!row) return;

        const lines = [`<div class="font-medium text-primary mb-1">${row.dateLabel}</div>`];
        let total = 0;
        layers.forEach((layer) => {
          const v = Number(row[layer.key]) || 0;
          if (v <= 0) return;
          total += v;
          lines.push(
            `<div class="flex items-center justify-between gap-3"><span class="min-w-0 flex items-center gap-1"><span style="color:${layer.color}">●</span><span class="text-secondary truncate">${layer.name}</span></span><span class="shrink-0 tabular-nums">${moneyFmt.format(v)}</span></div>`
          );
        });
        lines.push(
          `<div class="mt-1 pt-1 border-t border-primary font-medium tabular-nums">${moneyFmt.format(total)}</div>`
        );
        tooltip.html(lines.join(""));
        const rect = elBox();
        tooltip.style("opacity", 1).style("left", `${event.clientX - rect.left + 12}px`).style("top", `${event.clientY - rect.top + 12}px`);
      })
      .on("mouseleave", () => {
        tooltip.style("opacity", 0);
      });
  }
}

