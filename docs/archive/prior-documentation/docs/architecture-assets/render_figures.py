"""Rebuild the EnerCubix architecture PNGs with Python 3 and Pillow."""

from argparse import ArgumentParser
from math import atan2, cos, sin
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


SCALE = 2
WIDTH = 820
PAPER = "#F7FAFB"
WHITE = "#FFFFFF"
INK = "#153047"
MUTED = "#455E70"
LINE = "#C6D6DE"
EDGE = "#648196"
TEAL = "#0A645E"
TEAL_BG = "#E6F3EF"
BLUE = "#275982"
BLUE_BG = "#EAF1FA"
AMBER = "#845525"
AMBER_BG = "#FCF2E5"
OUTPUT = Path(__file__).resolve().parent


class Diagram:
    def __init__(self, height, number, heading, subtitle, regular, bold):
        self.image = Image.new("RGB", (WIDTH * SCALE, height * SCALE), PAPER)
        self.draw = ImageDraw.Draw(self.image)
        self.regular = regular
        self.bold = bold
        self.fonts = {}
        self.box(31, 26, 44, 36, fill=TEAL, stroke=TEAL, radius=7)
        self.label(53, 44, number, 18, WHITE, bold=True, anchor="mm")
        self.label(89, 24, heading, 28, bold=True)
        self.label(90, 61, subtitle, 17, MUTED)

    def font(self, size, bold):
        key = (size, bold)
        if key not in self.fonts:
            self.fonts[key] = ImageFont.truetype(
                str(self.bold if bold else self.regular), size * SCALE
            )
        return self.fonts[key]

    def label(self, x, y, value, size, color=INK, bold=False, anchor="lt", width=None):
        font = self.font(size, bold)
        if width is not None and self.draw.textlength(value, font=font) > width * SCALE:
            raise ValueError(f"Text overflows {width} logical pixels: {value}")
        self.draw.text((x * SCALE, y * SCALE), value, font=font, fill=color, anchor=anchor)

    def box(self, x, y, width, height, fill=WHITE, stroke=LINE, radius=10):
        self.draw.rounded_rectangle(
            (x * SCALE, y * SCALE, (x + width) * SCALE, (y + height) * SCALE),
            radius=radius * SCALE, fill=fill, outline=stroke, width=SCALE
        )

    def card(self, x, y, width, height, title, body=(), accent=TEAL, fill=WHITE):
        self.box(x, y, width, height, fill)
        self.label(x + 15, y + 12, title, 21, accent, bold=True, width=width - 30)
        for index, line in enumerate(body):
            self.label(x + 15, y + 42 + index * 23, line, 17, MUTED, width=width - 30)
        if body and 42 + (len(body) - 1) * 23 + 18 > height:
            raise ValueError(f"Body text overflows card: {title}")

    def arrow(self, *points, color=EDGE):
        scaled = [(x * SCALE, y * SCALE) for x, y in points]
        self.draw.line(scaled, fill=color, width=2 * SCALE, joint="curve")
        x, y = points[-1]
        previous_x, previous_y = points[-2]
        angle = atan2(y - previous_y, x - previous_x)
        self.draw.polygon(
            [
                (x * SCALE, y * SCALE),
                ((x - 10 * cos(angle - 0.53)) * SCALE, (y - 10 * sin(angle - 0.53)) * SCALE),
                ((x - 10 * cos(angle + 0.53)) * SCALE, (y - 10 * sin(angle + 0.53)) * SCALE),
            ],
            fill=color,
        )

    def banner(self, y, text, fill=TEAL_BG, color=TEAL):
        self.box(32, y, 756, 38, fill=fill, stroke=fill, radius=7)
        self.label(48, y + 10, text, 17, color, width=725)

    def save(self, filename):
        self.image.save(OUTPUT / filename, dpi=(240, 240), optimize=True)


def overview(regular, bold):
    d = Diagram(572, "01", "能源魔方总体架构", "FIN Framework 5.3.0.2761  /  EnerCubix 0.14.37", regular, bold)
    d.card(32, 102, 756, 70, "用户浏览器 · React / TypeScript",
           ("能源经营驾驶舱 · 分析工作台 · 报告模板 · 消息中心 · 配置管理",))
    d.arrow((410, 172), (410, 219))
    d.label(426, 185, "同源请求 · FIN 会话及权限", 17, MUTED)
    d.box(32, 220, 756, 288, fill=BLUE_BG, stroke="#ACC4DB")
    d.label(48, 233, "FIN 项目运行时", 20, BLUE, bold=True)
    d.box(48, 262, 724, 114, fill=TEAL_BG, stroke="#A8C9C0")
    d.label(63, 274, "EnerCubix Pod · Fantom", 20, TEAL, bold=True)
    d.card(63, 304, 216, 60, "接口与权限", ("REST / Axon 入口",))
    d.card(302, 304, 216, 60, "查询与计算", ("报表、驾驶舱与质量",))
    d.card(541, 304, 216, 60, "配置与消息", ("受控配置、变更与确认",))
    d.arrow((410, 376), (410, 418), color=BLUE)
    d.arrow((410, 402), (160, 402), (160, 418), color=BLUE)
    d.arrow((410, 402), (660, 402), (660, 418), color=BLUE)
    d.label(426, 381, "复用项目原生数据与服务", 16, BLUE)
    d.card(48, 418, 224, 75, "设备与 Folio", ("设备、点位及配置记录",), BLUE)
    d.card(298, 418, 224, 75, "原生历史", ("采集、归档和历史读取",), BLUE)
    d.card(548, 418, 224, 75, "原生报警", ("报警发生、确认与恢复",), BLUE)
    d.banner(523, "FIN 管理采集与历史。能源魔方负责业务配置、查询计算和结果呈现。")
    d.save("01-overview.png")


def device_views(regular, bold):
    d = Diagram(525, "02", "同一设备的三个视角", "空间、计量和组织各自表达一种关系", regular, bold)
    d.card(32, 104, 236, 100, "空间视角", ("站点、楼栋和楼层", "基于 FIN 原生空间归属"), BLUE, BLUE_BG)
    d.card(292, 104, 236, 100, "计量视角", ("设备当前的计量上级", "每台表计可设一个上级"), TEAL, TEAL_BG)
    d.card(552, 104, 236, 100, "组织视角", ("组织层级与设备归属", "按核算需要独立配置"), BLUE, BLUE_BG)
    d.arrow((150, 204), (150, 246))
    d.arrow((410, 204), (410, 246))
    d.arrow((670, 204), (670, 246))
    d.card(32, 246, 756, 94, "统一身份 · FIN 设备 Ref",
           ("主能耗点绑定、能源类型、分项用途及计量属性随设备记录管理。",
            "配置修订记录用于查询变更经过，统计按当前生效的配置解析。"))
    d.arrow((214, 340), (214, 378))
    d.arrow((606, 340), (606, 378))
    d.card(32, 378, 364, 100, "有效统计范围",
           ("按范围、类别和计量边界选表。", "识别同源别名与重叠上下级。"), BLUE)
    d.card(424, 378, 364, 100, "虚拟分类",
           ("多个虚拟分类可引用同一设备。", "公式引用与计量上级独立配置。"), TEAL)
    d.label(34, 491, "各表用量均来自各自主能耗点的 FIN 历史。", 17, MUTED)
    d.save("02-device-views.png")


def query_pipeline(regular, bold):
    d = Diagram(613, "03", "从主能耗点到报表", "驾驶舱和分析工作台复用基础用量及质量口径", regular, bold)
    steps = [
        ("确定查询条件", "按项目时区确定统计区间、数据截止及对比时段。"),
        ("解析有效表计", "按当前关系和能源类型确定范围、有效表计及其主点。"),
        ("读取 FIN 原生历史", "各表只读自身明确绑定的主能耗点历史，按需读取边界样本。"),
        ("计算基础用量和质量", "应用清洗方案，累计读数做差，区间值按语义汇总。"),
        ("计算业务指标并生成报告", "结合费率、系数、面积和工作日历，输出用量、质量及来源。"),
    ]
    for index, (title, text) in enumerate(steps):
        y = 100 + index * 90
        d.card(32, y, 756, 69, title, (text,), BLUE if index == 2 else TEAL,
               BLUE_BG if index == 2 else WHITE)
        if index < len(steps) - 1:
            d.arrow((410, y + 69), (410, y + 90))
    d.banner(543, "覆盖不足时保留已有量，区分缺测、NA 和真实零。", AMBER_BG, AMBER)
    d.save("03-query-pipeline.png")


def cockpit_snapshot(regular, bold):
    d = Diagram(613, "04", "驾驶舱快照与交付", "一次查询固定统计范围、截止时刻和该次结果", regular, bold)
    d.card(32, 100, 482, 83, "提交统计条件 · POST cockpit",
           ("范围、能源、时间、对比方式及所需模块",), BLUE, BLUE_BG)
    d.arrow((273, 183), (273, 212))
    d.arrow((514, 141), (662, 141), (662, 212), color=BLUE)
    d.card(32, 212, 482, 96, "规划读取并计算",
           ("解析有效表计，固定请求配置和范围。", "分块读取主点，复用请求内聚合结果。"))
    d.card(536, 212, 252, 96, "读取当前事件",
           ("观察 FIN 报警状态，", "记录独立的事件观测时刻。"), BLUE, BLUE_BG)
    d.arrow((273, 308), (273, 340))
    d.arrow((662, 308), (662, 340), color=BLUE)
    d.card(32, 340, 756, 100, "返回驾驶舱快照",
           ("快照 ID、统计边界、数据截止、质量、来源、模块结果与报告引用",
            "预算对照使用匹配的项目、统计边界、能源类型、币种和预算版本。"), TEAL, TEAL_BG)
    d.arrow((150, 440), (150, 480))
    d.arrow((410, 440), (410, 480))
    d.arrow((670, 440), (670, 480))
    d.card(32, 480, 236, 78, "首页与六个视图", ("共享已返回的统计结果",), BLUE)
    d.card(292, 480, 236, 78, "下钻与专业报告", ("同快照明细或按条件另查",), BLUE)
    d.card(552, 480, 236, 78, "交付与留证", ("汇报视图、Excel 及 JSON",), BLUE)
    d.label(34, 573, "数据截止与事件观测时刻分别记录。刷新后生成新的快照。", 17, MUTED)
    d.save("04-cockpit-snapshot.png")


def energy_flow(regular, bold):
    d = Diagram(591, "05", "计量关系与共享分表", "用量示例 · 所有成员单位均为 kWh", regular, bold)
    d.box(32, 101, 365, 324, fill=BLUE_BG, stroke="#ACC4DB")
    d.box(423, 101, 365, 324, fill=TEAL_BG, stroke="#A8C9C0")
    d.label(51, 115, "物理计量关系", 22, BLUE, bold=True)
    d.label(442, 115, "虚拟分类的成员引用", 22, TEAL, bold=True)
    d.card(51, 156, 327, 73, "总表 T · 110", ("读取总表 T 自身主点历史",), BLUE)
    d.arrow((215, 229), (215, 254), (131, 254), (131, 277), color=BLUE)
    d.arrow((215, 254), (299, 254), (299, 277), color=BLUE)
    d.card(51, 277, 158, 68, "分表 A", ("已有用量 40",), BLUE)
    d.card(220, 277, 158, 68, "分表 B", ("已有用量 60",), BLUE)
    d.label(51, 360, "计量差额为 10，前提是统计", 17, MUTED)
    d.label(51, 385, "范围与数据覆盖支持该判断。", 17, MUTED)
    d.card(442, 156, 327, 73, "分类 G1 · 引用 A", ("可计算的成员贡献为 40",))
    d.card(442, 242, 327, 73, "分类 G2 · 引用 A + B", ("可计算的成员贡献为 100",))
    d.label(442, 332, "A 是两个分类的共享成员。", 17, MUTED)
    d.label(442, 357, "纯加法且计量边界明确时，", 17, MUTED)
    d.label(442, 382, "G1 与 G2 的去重成员贡献为 100。", 17, MUTED)
    d.card(32, 446, 756, 92, "独立保留各对象的用量口径",
           ("虚拟表自身用量读取该表主点历史。贡献分析单独读取各成员的主点历史。",
            "多选对象分别展示图与依据，共享或不可加总时明确说明。"))
    d.label(34, 553, "空间与组织的连线表达用能分布。物理计量图按总分表关系表达平衡。", 17, MUTED)
    d.save("05-energy-flow.png")


def main():
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("--font", type=Path, default=Path("C:/Windows/Fonts/msyh.ttc"))
    parser.add_argument("--bold-font", type=Path, default=Path("C:/Windows/Fonts/msyhbd.ttc"))
    args = parser.parse_args()
    for render in (overview, device_views, query_pipeline, cockpit_snapshot, energy_flow):
        render(args.font, args.bold_font)


if __name__ == "__main__":
    main()
