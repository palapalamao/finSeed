"""Rebuild the English FIN Energy architecture diagrams with Pillow."""

from argparse import ArgumentParser
from pathlib import Path
import sys

OUTPUT = Path(__file__).resolve().parent
sys.path.insert(0, str(OUTPUT.parent))

from render_figures import AMBER, AMBER_BG, BLUE, BLUE_BG, Diagram, MUTED, TEAL, TEAL_BG, WHITE


class EnglishDiagram(Diagram):
    def save(self, filename):
        self.image.save(OUTPUT / filename, dpi=(240, 240), optimize=True)


def overview(regular, bold):
    d = EnglishDiagram(
        572, "01", "FIN Energy System Architecture",
        "FIN Framework 5.3.0.2761  /  FIN Energy 0.16.0", regular, bold
    )
    d.card(32, 102, 756, 70, "Browser · React / TypeScript",
           ("Energy cockpit · Analysis workspace · Report templates · Message center · Settings",))
    d.arrow((410, 172), (410, 219))
    d.label(426, 185, "Same-origin access via the FIN session", 17, MUTED)
    d.box(32, 220, 756, 288, fill=BLUE_BG, stroke="#ACC4DB")
    d.label(48, 233, "FIN Project Runtime", 20, BLUE, bold=True)
    d.box(48, 262, 724, 114, fill=TEAL_BG, stroke="#A8C9C0")
    d.label(63, 274, "FIN Energy Pod · Fantom", 20, TEAL, bold=True)
    d.card(63, 304, 216, 60, "Interfaces", ("REST / Axon access",))
    d.card(302, 304, 216, 60, "Analytics", ("Reports, cockpit, quality",))
    d.card(541, 304, 216, 60, "Configuration", ("Settings and messages",))
    d.arrow((410, 376), (410, 418), color=BLUE)
    d.arrow((410, 402), (160, 402), (160, 418), color=BLUE)
    d.arrow((410, 402), (660, 402), (660, 418), color=BLUE)
    d.label(426, 381, "Reuse native project data and services", 16, BLUE)
    d.card(48, 418, 224, 75, "Devices and Folio", ("Device and point records",), BLUE)
    d.card(298, 418, 224, 75, "Native History", ("Collect, store, read",), BLUE)
    d.card(548, 418, 224, 75, "Native Alarms", ("Raise, ack, and recover",), BLUE)
    d.banner(523, "FIN manages collection and history. FIN Energy manages settings, analytics, and presentation.")
    d.save("01-overview.png")


def device_views(regular, bold):
    d = EnglishDiagram(
        525, "02", "One Device Across Three Views",
        "Space, metering, and organization each describe a distinct relationship.", regular, bold
    )
    d.card(32, 104, 236, 100, "Space View", ("Sites, buildings, floors", "Native FIN space links"), BLUE, BLUE_BG)
    d.card(292, 104, 236, 100, "Metering View", ("Current metering parent", "One parent per meter"), TEAL, TEAL_BG)
    d.card(552, 104, 236, 100, "Organization View", ("Hierarchy and assignments", "Configured independently"), BLUE, BLUE_BG)
    d.arrow((150, 204), (150, 246))
    d.arrow((410, 204), (410, 246))
    d.arrow((670, 204), (670, 246))
    d.card(32, 246, 756, 94, "Shared Identity · FIN Device Ref",
           ("Device records hold the primary point binding, energy category, end use, and metering settings.",
            "Revision history records changes. Queries use the current effective configuration."))
    d.arrow((214, 340), (214, 378))
    d.arrow((606, 340), (606, 378))
    d.card(32, 378, 364, 100, "Effective Scope",
           ("Select meters by scope and energy type.", "Detect aliases and overlapping ancestry."), BLUE)
    d.card(424, 378, 364, 100, "Virtual Classifications",
           ("Multiple classifications can share a device.", "Formulas and parent links are separate."), TEAL)
    d.label(34, 491, "Each meter's consumption comes from its own primary energy point history in FIN.", 17, MUTED)
    d.save("02-device-views.png")


def query_pipeline(regular, bold):
    d = EnglishDiagram(
        613, "03", "From Primary Energy Points to Reports",
        "The cockpit and workspace share consumption and data quality rules.", regular, bold
    )
    steps = [
        ("Set Query Criteria", "Resolve the interval, cutoff, and comparison period in the project time zone."),
        ("Resolve Effective Meters", "Use current relationships and energy category to find meters and their primary points."),
        ("Read Native FIN History", "Read each meter's bound primary point history and request boundary samples as needed."),
        ("Calculate Consumption and Quality", "Apply cleaning rules, difference cumulative readings, and aggregate interval quantities."),
        ("Calculate Metrics and Build Reports", "Apply tariffs, factors, area, and calendars. Return consumption, quality, and sources."),
    ]
    for index, (title, detail) in enumerate(steps):
        y = 100 + index * 90
        d.card(32, y, 756, 69, title, (detail,), BLUE if index == 2 else TEAL,
               BLUE_BG if index == 2 else WHITE)
        if index < len(steps) - 1:
            d.arrow((410, y + 69), (410, y + 90))
    d.banner(543, "Keep available consumption when coverage is partial. Distinguish missing, NA, and true zero.",
             AMBER_BG, AMBER)
    d.save("03-query-pipeline.png")


def cockpit_snapshot(regular, bold):
    d = EnglishDiagram(
        613, "04", "Cockpit Snapshot and Delivery",
        "Each query fixes the scope, cutoff, and results for one snapshot.", regular, bold
    )
    d.card(32, 100, 482, 83, "Submit Criteria · POST /cockpit",
           ("Scope, energy, time, comparison, and modules",), BLUE, BLUE_BG)
    d.arrow((273, 183), (273, 212))
    d.arrow((514, 141), (662, 141), (662, 212), color=BLUE)
    d.card(32, 212, 482, 96, "Plan Reads and Calculate",
           ("Resolve meters and freeze configuration and scope.", "Read primary points in chunks and reuse query aggregates."))
    d.card(536, 212, 252, 96, "Read Current Events",
           ("Observe FIN alarm state.", "Record the observation time."), BLUE, BLUE_BG)
    d.arrow((273, 308), (273, 340))
    d.arrow((662, 308), (662, 340), color=BLUE)
    d.card(32, 340, 756, 100, "Return Cockpit Snapshot",
           ("Snapshot ID, scope, cutoff, quality, sources, module results, and report references",
            "Budget comparison matches project, scope, energy category, currency, and version."), TEAL, TEAL_BG)
    d.arrow((150, 440), (150, 480))
    d.arrow((410, 440), (410, 480))
    d.arrow((670, 440), (670, 480))
    d.card(32, 480, 236, 78, "Home and Six Views", ("Reuse returned results",), BLUE)
    d.card(292, 480, 236, 78, "Drilldown / Reports", ("Details or a new query",), BLUE)
    d.card(552, 480, 236, 78, "Briefing and Export", ("Briefing, Excel, and JSON",), BLUE)
    d.label(34, 573, "The data cutoff and event observation time are separate. Refresh creates a new snapshot.",
            17, MUTED, width=754)
    d.save("04-cockpit-snapshot.png")


def energy_flow(regular, bold):
    d = EnglishDiagram(
        591, "05", "Metering Relationships and Shared Submeters",
        "Consumption example · All values are in kWh.", regular, bold
    )
    d.box(32, 101, 365, 324, fill=BLUE_BG, stroke="#ACC4DB")
    d.box(423, 101, 365, 324, fill=TEAL_BG, stroke="#A8C9C0")
    d.label(51, 115, "Physical Metering", 22, BLUE, bold=True)
    d.label(442, 115, "Virtual Classification Members", 22, TEAL, bold=True)
    d.card(51, 156, 327, 73, "Main Meter T · 110", ("Read T's own primary point history.",), BLUE)
    d.arrow((215, 229), (215, 254), (131, 254), (131, 277), color=BLUE)
    d.arrow((215, 254), (299, 254), (299, 277), color=BLUE)
    d.card(51, 277, 158, 68, "Submeter A", ("Available: 40",), BLUE)
    d.card(220, 277, 158, 68, "Submeter B", ("Available: 60",), BLUE)
    d.label(51, 360, "The meter difference is 10 if scope and", 17, MUTED, width=327)
    d.label(51, 385, "coverage support that calculation.", 17, MUTED, width=327)
    d.card(442, 156, 327, 73, "G1 · References A", ("Calculated member contribution: 40",))
    d.card(442, 242, 327, 73, "G2 · References A + B", ("Calculated member contribution: 100",))
    d.label(442, 332, "Both classifications share A.", 17, MUTED, width=327)
    d.label(442, 357, "With addition only and a clear boundary,", 17, MUTED, width=327)
    d.label(442, 382, "their deduplicated contribution is 100.", 17, MUTED, width=327)
    d.card(32, 446, 756, 92, "Keep Each Object's Consumption Basis",
           ("Virtual meters and their members each use their own primary point history.",
            "Each object has its own diagram and basis, with overlaps and aggregation limits shown."))
    d.label(34, 553, "Space and organization links show distribution. Physical metering links show parent–child balance.",
            17, MUTED, width=754)
    d.save("05-energy-flow.png")


def native_licensing(regular, bold):
    d = EnglishDiagram(
        572, "06", "Native FIN Feature Activation",
        "HQ confirmed finenergy. Native runtime acceptance needs a genuine test license.", regular, bold
    )
    d.card(32, 124, 224, 111, "HQ Licensing",
           ("Native licensing service", "Issues a finenergy license"), BLUE)
    d.card(298, 124, 224, 111, "FIN Native Check",
           ("Exact feature match", "License validity"), BLUE)
    d.card(564, 124, 224, 111, "FIN Energy Extension",
           ("FinExt feature gate", "Read-only native status"), BLUE)
    d.arrow((256, 179), (298, 179), color=BLUE)
    d.arrow((522, 179), (564, 179), color=BLUE)
    d.arrow((410, 235), (410, 270), (214, 270), (214, 300))
    d.arrow((410, 270), (607, 270), (607, 300))
    d.card(32, 300, 365, 110, "Valid Feature",
           ("The extension starts", "Verify license state and access"))
    d.card(423, 300, 365, 110, "Missing, Invalid, or Expired",
           ("The extension can be inactive", "Use native FIN Host licensing"), AMBER)
    d.label(34, 441, "FIN retains raw history. Runtime acceptance checks raw reads, normal reads, and cleaning.",
            17, MUTED, width=752)
    d.banner(495, "The exact feature ID is finenergy, in lowercase with no spaces.")
    d.save("06-native-licensing.png")


def main():
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("--font", type=Path, default=Path("C:/Windows/Fonts/arial.ttf"))
    parser.add_argument("--bold-font", type=Path, default=Path("C:/Windows/Fonts/arialbd.ttf"))
    args = parser.parse_args()
    for render in (overview, device_views, query_pipeline, cockpit_snapshot, energy_flow, native_licensing):
        render(args.font, args.bold_font)


if __name__ == "__main__":
    main()
