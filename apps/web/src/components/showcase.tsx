export function Showcase() {
  return (
    <section className="bg-brand-950 py-24 sm:py-32">
      <div className="mx-auto max-w-6xl px-6">
        <h2 className="mb-4 text-center text-3xl font-bold text-white sm:text-4xl">
          Built with just-ship
        </h2>
        <p className="mx-auto mb-16 max-w-xl text-center text-brand-400">
          Real products, shipping autonomously. Every PR reviewed by a human —
          built by agents.
        </p>

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {/* Card 1 — Aime */}
          <div className="rounded-2xl border border-brand-800 bg-brand-900 p-8 text-center transition-colors hover:border-brand-700">
            <div
              className="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-xl text-xl font-extrabold text-white"
              style={{ background: "linear-gradient(135deg, #3b82f6, #8b5cf6)" }}
            >
              A
            </div>
            <p className="mb-1.5 text-[15px] font-semibold text-white">Aime</p>
            <p className="text-xs leading-relaxed text-brand-500">
              AI-powered productivity platform. Newsletter, entries, and more.
            </p>
            <div className="mt-4 border-t border-brand-800 pt-4">
              <p className="font-mono text-lg font-bold text-accent">300+</p>
              <p className="mt-0.5 text-[11px] text-brand-600">tickets shipped</p>
            </div>
          </div>

          {/* Card 2 — 19ELF */}
          <div className="rounded-2xl border border-brand-800 bg-brand-900 p-8 text-center transition-colors hover:border-brand-700">
            <div
              className="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-xl text-xl font-extrabold text-white"
              style={{ background: "linear-gradient(135deg, #10b981, #059669)" }}
            >
              19
            </div>
            <p className="mb-1.5 text-[15px] font-semibold text-white">19ELF</p>
            <p className="text-xs leading-relaxed text-brand-500">
              Website built and maintained entirely through just-ship pipeline.
            </p>
            <div className="mt-4 border-t border-brand-800 pt-4">
              <p className="font-mono text-lg font-bold text-accent">100%</p>
              <p className="mt-0.5 text-[11px] text-brand-600">autonomous delivery</p>
            </div>
          </div>

          {/* Card 3 — just-ship */}
          <div className="rounded-2xl border border-accent/20 bg-brand-900 p-8 text-center transition-colors hover:border-brand-700">
            <div className="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-xl bg-accent/10 text-xl font-extrabold text-accent">
              &#9650;
            </div>
            <p className="mb-1.5 text-[15px] font-semibold text-white">just-ship</p>
            <p className="text-xs leading-relaxed text-brand-500">
              This framework. Built, maintained, and evolved with itself.
            </p>
            <div className="mt-4 border-t border-brand-800 pt-4">
              <p className="font-mono text-sm font-bold text-accent">meta</p>
              <p className="mt-0.5 text-[11px] text-brand-600">self-improving</p>
            </div>
          </div>

          {/* Card 4 — & more */}
          <div className="rounded-2xl border border-brand-800 bg-brand-900 p-8 text-center transition-colors hover:border-brand-700">
            <div
              className="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-xl text-xl font-extrabold text-white"
              style={{ background: "linear-gradient(135deg, #f59e0b, #d97706)" }}
            >
              +
            </div>
            <p className="mb-1.5 text-[15px] font-semibold text-white">& more</p>
            <p className="text-xs leading-relaxed text-brand-500">
              Multiple client projects shipping daily with just-ship agents.
            </p>
            <div className="mt-5">
              <p className="text-sm text-brand-400">90%+ success rate</p>
              <p className="mt-0.5 text-[11px] text-brand-600">
                tickets → PRs without intervention
              </p>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
