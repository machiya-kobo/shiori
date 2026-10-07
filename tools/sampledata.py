# SPDX-License-Identifier: AGPL-3.0-or-later
"""sampledata: the invented sample pages and notes behind every screenshot and
test run that shows content: the paper-lantern workshop and the Kyoto trip
of Machiya's sample vault, on hosts under .example. Nobody's real history.

Used by tools/quickstart/seed-hister.py (the pages, into a local Hister),
tools/screenshots (the notes, from its stand-in Kura) and
haiku/fake-services.py (both, for Shiori for Classic Macintosh's and Haiku's
UI runs). Standard library only; importing it does nothing else.
"""
import time

DAY = 86400
NOW = int(time.time()) // DAY * DAY
# (url, title, label, text, days ago): the paper-lantern workshop and the
# Kyoto trip of Machiya's sample vault.
PAGES = [
    ("https://lanterns.example/chochin-folding", "Folding a chōchin lantern", "lanterns",
     "A chōchin collapses flat: a spiral bamboo rib under washi, folded along each turn of the spiral.", 0),
    ("https://lanterns.example/bamboo-frames", "Bending bamboo frames with steam", "lanterns",
     "Steam the split bamboo for ten minutes, bend it round a jig, and let it set overnight.", 1),
    ("https://washi.example/making", "How washi paper is made", "paper",
     "Kozo bark is soaked, beaten and spread on a screen; the long fibres make the paper strong.", 1),
    ("https://washi.example/kinds", "Kozo, mitsumata and gampi", "paper",
     "Three plants give washi its character: kozo is tough, mitsumata smooth, gampi glossy.", 2),
    ("https://paste.example/nori", "Nori paste for paper and bamboo", "workshop",
     "Wheat-starch nori paste holds washi to bamboo and stays reversible with a damp brush.", 3),
    ("https://light.example/candle-vs-led", "Candle or LED inside a paper lantern?", "lanterns",
     "A candle gives a warm flicker but scorches washi; a warm-white LED runs cool and safe.", 4),
    ("https://bamboo.example/sourcing", "Sourcing bamboo for craft work", "workshop",
     "Cut madake in winter, when the culms hold less sugar and resist beetles.", 5),
    ("https://kyoto.example/lantern-festival", "Kyoto's summer lantern festival", "travel",
     "Thousands of lanterns line the lanes after dark; arrive early and walk up from the river.", 6),
    ("https://kyoto.example/machiya", "Staying in a Kyoto machiya townhouse", "travel",
     "Machiya are narrow wooden townhouses with a shop at the front and a small garden at the back.", 8),
    ("https://travel.example/packing-japan", "Packing light for two weeks in Japan", "travel",
     "One carry-on, layers, slip-on shoes for temples, and a small towel for the trains.", 10),
    ("https://workbench.example/layout", "Laying out a small craft workbench", "workshop",
     "Keep cutting on the left, gluing on the right, and drying racks above the bench.", 12),
    ("https://lanterns.example/restoring", "Restoring an old paper lantern", "lanterns",
     "Strip the torn washi, re-glue loose ribs with nori, and re-cover one panel at a time.", 15),
]



# (path in the vault without .md, tags, days ago, summary, checklist items)
NOTES = [
    ("Projects/Lantern festival kit", ["lanterns", "festival"], 1,
     "Everything for the summer lantern festival stall: six folded chōchin, warm-white LED inserts, spare washi, "
     "a jar of nori paste and the folding stand.",
     ["Six chōchin, folded flat in the long box", "Twelve LED inserts and spare batteries",
      "Kozo washi offcuts for repairs", "Nori paste and a soft brush", "The folding stand and its pegs"]),
    ("Workshop/Chōchin build log", ["lanterns", "workshop"], 2,
     "Day three: the spiral rib held its shape after steaming, and the lantern took its washi in four panels.",
     ["Steam the rib for ten minutes", "Bend it round the jig", "Paste the panels top to bottom"]),
    ("Workshop/Washi offcuts", ["paper"], 4,
     "Keep kozo offcuts for patching torn lantern panels; gampi is too glossy to take the paste.",
     ["Kozo: patches and new panels", "Mitsumata: labels", "Gampi: not for lanterns"]),
    ("Travel/Kyoto trip plan", ["travel"], 7,
     "Two nights in a machiya near the river, with the lantern festival on the second evening.",
     ["Day 1: arrive, walk the river", "Day 2: the lantern festival after dark", "Day 3: the washi shops"]),
    ("Workshop/Nori paste recipe", ["workshop"], 9,
     "One part wheat starch to five of water, cooked slowly until it turns clear.",
     ["Stir all the way", "Strain it while warm", "Keep it a week in the cold"]),
]
