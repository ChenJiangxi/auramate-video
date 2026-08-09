#!/usr/bin/env python3
"""check-compliance.py — 命理/玄学题材内容合规自检。

一句话原则：**宣扬封建迷信必违规；讲 AI 算命、讲产品功能不违规。**
详见 skills/compliance-redlines/SKILL.md

扫描 clips.json（口播稿）/ topic.md（选题）/ caption.txt（平台文案），分三档：
  BLOCK  出现即必须改 —— 退出码 1
  WARN   高风险，人工确认这句在说什么
  INFO   建议项（例如全片没有任何「参考/娱乐/文化」框定话术）

用法:
  /usr/bin/python3 lib/check-compliance.py --project <dir>
  /usr/bin/python3 lib/check-compliance.py --file caption.txt
  /usr/bin/python3 lib/check-compliance.py --text "随便一段话"
  加 --strict 让 WARN 也算失败（交付前建议开）

局限：机器只查词，查不了语义。否定式表达（"不用改运"）会误报，人工判一下即可；
不含高危词但整体在承诺祸福的片子，机器也拦不住。**最终判断在人。**
"""
import argparse, json, os, re, sys

# ---- BLOCK：出现即必须改。value = 怎么改 ----
BLOCK = {
    # 承诺改变命运
    '转运': '删掉，不替换 —— 承诺改命是明确违规', '改运': '删掉，不替换',
    '改命': '删掉，不替换', '开运': '删掉，不替换',
    '旺财': '删掉，不替换', '旺夫': '删掉，不替换', '续命': '删掉，不替换',
    # 消灾解厄
    '消灾': '删掉，不替换', '挡煞': '删掉，不替换', '保平安': '删掉，不替换',
    '破财免灾': '删掉，不替换', '化解灾': '删掉，不替换', '化太岁': '删掉，不替换',
    # 迷信仪式
    '开光': '删掉，不替换', '符咒': '删掉，不替换', '画符': '删掉，不替换',
    '做法事': '删掉，不替换', '招财阵': '删掉，不替换', '请神': '删掉，不替换',
    # 预言具体祸福
    '血光之灾': '删掉，不替换', '犯太岁': '删掉；要讲太岁只能讲民俗源流，不能讲后果',
    '断生死': '删掉，不替换', '有大难': '删掉，不替换',
    # 恐吓营销
    '不看必悔': '删掉，不替换', '不改会出事': '删掉，不替换', '躲不过': '改成描述性表达',
    # 神化 / 虚假宣传
    '大师亲算': '删掉，不替换', '神准': '删掉，不替换', '包准': '删掉，不替换',
    '百分百准': '删掉，不替换', '必定应验': '删掉，不替换', '灵验': '删掉，不替换',
    # 算命引流（玄学 + 私域 = 处罚最重的组合）
    '加微信': '删掉 —— 玄学题材引导私加是重点打击对象', '私信我算': '删掉，不替换',
    '扫码进群': '删掉，不替换', '免费测算': '删掉，不替换', '给你算一卦': '改成「看看传统命理怎么描述这类人」',
    '算你的命': '改成「看看传统命理怎么描述这类人」',
}

# ---- WARN：高风险，需要人工确认 ----
WARN = {
    '预测': '改成「描述 / 参考 / 这套说法里」', '预言': '改成「描述 / 参考」',
    '注定': '改成「倾向于 / 常被描述为」', '命中注定': '改成「传统说法里…」',
    '必然': '改成「更容易 / 倾向于」', '一定会': '改成「倾向于」',
    '劫难': '只做描述，不做结论', '厄运': '只做描述，不做结论',
    '吉凶': '只做描述，不做判决', '冲太岁': '只讲民俗源流，不讲后果',
    '治好': '命理不碰医疗 —— 不给诊断和治疗建议', '治愈': '命理不碰医疗',
    '病根': '命理不碰医疗', '确诊': '命理不碰医疗', '处方': '命理不碰医疗',
    '吃什么药': '命理不碰医疗',
    '一夜暴富': '不给财务决策指引', '财运暴涨': '不给财务决策指引',
    '该不该买': '不给投资建议', '稳赚': '不给投资建议',
    '克夫': '不对真实关系下判决', '克妻': '不对真实关系下判决',
    '必须分手': '不对真实关系下判决',
}

# ---- 框定话术：全片至少出现一次，把结果定性为参考/文化/娱乐 ----
FRAMING = ['参考', '娱乐', '传统文化', '文化', '自我认知', '自我觉察', '换个角度',
           '你自己判断', '说法', '民俗', '国学']

AP = argparse.ArgumentParser()
AP.add_argument('--project', help='视频工程目录（扫 clips.json / topic.md / caption.txt）')
AP.add_argument('--file', action='append', default=[], help='指定文件，可重复')
AP.add_argument('--text', help='直接检查一段文字')
AP.add_argument('--strict', action='store_true', help='WARN 也算失败')
A = AP.parse_args()

sources = []          # (label, text)
if A.text:
    sources.append(('--text', A.text))
for f in A.file:
    if os.path.exists(f):
        sources.append((f, open(f, encoding='utf-8').read()))
    else:
        sys.exit(f'文件不存在: {f}')
if A.project:
    P = os.path.abspath(A.project)
    cj = os.path.join(P, 'clips.json')
    if os.path.exists(cj):
        for c in json.load(open(cj, encoding='utf-8')):
            sources.append((f"clips.json:{c.get('name','?')}", c.get('text', '')))
    for fn in ('topic.md', 'caption.txt'):
        p = os.path.join(P, fn)
        if os.path.exists(p):
            sources.append((fn, open(p, encoding='utf-8').read()))
if not sources:
    sys.exit('没东西可查。用 --project <dir> / --file <path> / --text "..."')

blocks, warns = [], []
all_text = ''.join(t for _, t in sources)

for label, text in sources:
    for word, fix in BLOCK.items():
        if word in text:
            blocks.append((label, word, fix, text))
    for word, fix in WARN.items():
        if word in text:
            warns.append((label, word, fix, text))


def excerpt(text, word, span=14):
    i = text.find(word)
    a, b = max(0, i - span), min(len(text), i + len(word) + span)
    return ('…' if a else '') + text[a:b].replace('\n', ' ') + ('…' if b < len(text) else '')


print(f'== 合规自检 —— {len(sources)} 段文本')
for label, word, fix, text in blocks:
    print(f'  ✗ BLOCK [{label}] 「{word}」')
    print(f'      {excerpt(text, word)}')
    print(f'      → {fix}')
for label, word, fix, text in warns:
    print(f'  ! WARN  [{label}] 「{word}」')
    print(f'      {excerpt(text, word)}')
    print(f'      → {fix}')

framed = any(k in all_text for k in FRAMING)
if not framed:
    print('  ○ INFO  全片没有任何框定话术 —— 建议至少出现一次把结果定性为')
    print('      「参考 / 自我觉察 / 传统文化说法 / 娱乐」的表述（自然带过，别念免责声明）')

print()
print(f'  BLOCK {len(blocks)} · WARN {len(warns)} · 框定话术 {"有" if framed else "无"}')
if blocks:
    print('  → 有 BLOCK，必须改完再往下走。词表和改法见 skills/compliance-redlines/SKILL.md')
elif warns:
    print('  → 没有 BLOCK。WARN 需要人工确认这几句到底在说什么。')
else:
    print('  → 词表层面干净。但机器查不了语义，交付前仍要过「三问」：')
    print('     ① 有没有承诺玄学结果？② 有没有替代医疗/投资决策？')
    print('     ③ 拿掉产品后，这条片子是在科普/讲技术/讲情绪，还是在提供占卜服务？')

sys.exit(1 if blocks or (A.strict and warns) else 0)
