# Node Leaf

**Node Leaf** is a visual, node-based RAG studio and prompt orchestration engine. Built in Flutter. Runs entirely on your machine, against your corpus, through your local LLMs via **Ollama**.

> ### ⚠️ Node Leaf requires Redleaf
> Node Leaf is the **One half of a Two-part system**. It is the reasoning canvas; the **[Redleaf Knowledge Engine](https://github.com/nathanfx330/redleaf)** is the ground it stands on — the Flask server that ingests your documents and media, builds the full-text and semantic indexes, extracts entities into a knowledge graph, and serves it all through the API every Node Leaf agent depends on.
>
> **Without a running Redleaf instance and an ingested corpus, Node Leaf has nothing to retrieve, nothing to cite, and nothing to verify against.** Install and populate [Redleaf](https://github.com/nathanfx330/redleaf) first; then come back and give it a canvas.

Blog: [Node Leaf](https://nathanielwestveer.com/posts/node-leaf/) · [The Agentic Wiki](https://nathanielwestveer.com/posts/agentic-wiki/) · [Why Chat Doesn't Scale for Deep Research](https://nathanielwestveer.com/posts/redleaf-engine-2-5/)

![Node Leaf](https://nathanielwestveer.com/posts/node-leaf/nl2.png)  

---

## Why This Exists

Modern AI chat interfaces have two structural flaws, and no amount of model improvement fixes either one.

**The first flaw is the interface itself.** A chat box is linear and opaque. It makes it difficult to group ideas, test variations, or hand a model complex context beyond its training data — and when the model stumbles on unfamiliar territory, you get rejection or hallucination, with no way to see what it was actually working from. This is an alignment problem, and Node Leaf's position is that it should be solved **at the interface level**: replace the box with an infinite canvas where context retrieval is a transparent, visual pipeline. Targeted nodes query exact entities, documents, and catalogs. A scratchpad lets you preview and *correct* retrieved data before the model ever sees it. Analysis can be injected at any point, and branches explored without collapsing the context window. The prompt stops being a prayer and becomes a program — one you can see, rearrange, and audit.

**The second flaw is ephemerality.** You can spend hours curating inputs and refining ideas in a session — and the moment it ends, the structure collapses. What remains is not a system but a transcript. Return a month later and you don't continue forward; you reconstruct from fragments. Node Leaf replaces this with the **Agentic Wiki**: agents that maintain a persistent, evolving body of knowledge as plain, portable Markdown, reading their own prior work, hunting the corpus for what's missing, and rewriting the pages — permanently, with versioned backups.

This is not output.
It is memory.

The shift is subtle but fundamental: from stateless interaction to **continuous cognition**.

---

## The Architecture of Trust

One principle organizes everything: **separate raw information from synthesized knowledge.**

* **Source of Truth:** immutable Redleaf documents.
* **Working Knowledge:** continuously rewritten Markdown pages.

Between the two runs a contract of *epistemological integrity*. Every claim stays anchored to its source through clickable `[Doc X]` citations. Contradictions are preserved explicitly rather than silently overwritten — *"earlier analysis suggested X; newly examined [Doc Y] indicates Z."* Every write is versioned to a hidden `.history` directory before modification. Version control, without the friction.

And where the corpus is audiovisual, the contract runs deeper still: quotes extracted from transcripts are **machine-verified verbatim** against the source subtitles and stamped with their true timecodes — by code, not by the model. Wrong citations are rewritten. Invented timestamps are relocated to where the words were actually spoken. Fabrications are deleted. The model proposes; the code disposes. Tap a citation, and hear the audio.

---

## ✨ Key Features

* **Visual Prompt Programming:** Drag, drop, and wire nodes into context chains on an infinite canvas. Data flows top to bottom through a DAG, accumulating meaning until an execution node spends it.
* **True Agency over Redleaf:** Agents hold programmatic, read-only access to your Redleaf Flask API — running hybrid FTS searches, walking knowledge-graph triplets, and pulling document pages to gather ground truth *before* answering, not instead of it.
* **Autonomous Research Loops (ReAct):** *Deep Study* and *Research Party* agents reason iteratively about what they don't know — formulating queries, fetching results, taking notes, hunting recursively — all streamed live so you can watch them think.
* **The Agentic Wiki (Infinite Memory):** A continuous synthesis loop — read current state, identify gaps, rewrite and persist — over local Markdown with Git-style backups. The system does not forget. It does not reset. It improves.
* **A Local Knowledge Graph:** Node Leaf parses `[[Wiki Link]]` syntax and runs a Markov-chain NodeRank over your pages — including the pages that *don't exist yet*, ranked by how badly your wiki demands them. Link rot becomes a writing queue.
* **Steerable Multi-Agent Debates (HITL):** Unguided agent swarms waste compute — they wander, and your GPU burns heat on outputs you don't care about. The Wiki Council is bounded by your Directive, and pauses mid-debate for the **Chairman's Review**, where you read the live transcript and rein the experts in before synthesis.
* **Manufactured Serendipity:** The Research Party treats your existing wiki as "unverified rumors," collides it against the raw corpus, and returns a cited Campfire Report of what you didn't know you had. The agentic "I'm Feeling Lucky."
* **A Verified Media Pipeline:** Feed SRT transcripts into the *Media Compressor* for documentary-style paper edits — every quote machine-verified verbatim, every timestamp real. Long footage is processed reel-by-reel, sized to your model and GPU.
* **In-Canvas Audition:** With media linked in Redleaf (local file or Archive.org), every cut grows a play chip — tap to hear the clip at its true timecode via `ffplay`/`mpv`. No audio plugins. No new dependencies.
* **Hardware Self-Calibration:** Media agents probe each model's context window, measure its real chars-per-token ratio from Ollama telemetry, back off under VRAM pressure, and remember what your card can handle. A 90-minute interview cuts cleanly on a 12GB GPU.
* **Interactive Reading:** `[Doc X]` citations and `[[Wiki Links]]` are clickable everywhere — hop between an agent's claim, its source document, and the wiki page without leaving the canvas. Missing pages spawn Deep Study nodes: knowledge gaps become actionable.
* **100% Local & Private:** One connection to Redleaf, one to Ollama. No cloud APIs, no telemetry, no terms of service between you and your research.
* **Project Management:** Save layouts as `.nlf` files — with an instance lock binding each project to the Redleaf database it was built against, so entity references can never silently point at the wrong corpus.
* **A Real Canvas:** Infinite pan/zoom, lasso selection, copy/paste, undo, and cycle-guarded wiring that refuses connections which would silently swallow your context.

---

## 🧩 The Node Ecosystem

Node Leaf is a Directed Acyclic Graph. Context flows from top to bottom and accumulates until an execution node spends it.

### Context & Prompt Nodes
* **➕ Scratchpad:** The basic building block — instructions, notes, attached Redleaf Entity Pills, with a dual-tab Edit/Read interface.
* **🎭 Agent Persona:** Define the role, tone, and worldview the model must inhabit downstream.
* **🗺️ System Briefing:** Injects a statistical overview of your Redleaf database, so agents know the shape of the corpus before diving in.
* **📘 Wiki Reader:** Loads a Markdown page from your local wiki into context.

### Redleaf Retrieval Nodes
* **🔍 Global Search:** Hybrid full-text search across the database; top snippets flow downstream.
* **📄 Document Reader:** The full raw text of a specific Document ID.
* **🗂️ Catalog Reader:** Context from an entire user-curated collection.
* **🔗 Graph Relationship:** Structured triplets for an entity, pulled from the Redleaf knowledge graph.
* **🎯 Co-Mention:** Pages where multiple entities are mentioned together.
* **🎬 Media/SRT Reader:** A timestamped transcript from a Redleaf media document — with an editor's brief, pinned curation comments, entity pills, and time-window selection (`1 + time: 00:45:00-01:15:00`) when only part of the footage matters.

### Execution Nodes
* **✨ Ollama Output:** Compiles everything upstream and writes the final response.
* **📝 Summarizer:** High-speed, loop-free condensation of upstream context.
* **💬 Ollama Chat:** Turns the upstream graph into a system prompt for a live, continuous conversation.
* **🤓 Deep Study (Geek Out):** Give it a topic; it loops through Redleaf — searching, reading, note-taking — until it can write the master report.
* **🏕️ Research Party:** Scout, Forager, and Chronicler chart the unknown: the Scout reads your wiki as rumor, the Forager extracts hard cited facts from unmapped corners of the corpus, the Chronicler returns a grounded Campfire Report of genuinely new territory.
* **🎞️ Media Compressor:** A robotic edit-bay assistant. Wire in a Media Reader and it delivers a paper edit — your target number of cuts, verbatim dialogue, exact timestamps. Long transcripts split into reels sized to your hardware; a deterministic QC pass verifies every quote against the source cues before anything reaches you. Linked media makes each cut playable in-panel, and the output port feeds the cutlist downstream.
* **🖋️ Wiki Writer:** A strict fact-checker. It reconciles upstream research with the current wiki state, resolves contradictions, and permanently writes the result — with preview and restore for older versions. Consumes Compressor cutlists and Media Readers directly, so footage becomes wiki pages with timestamped `[Doc X @ HH:MM:SS]` citations.
* **🏛️ Wiki Council:** A steerable Mixture-of-Experts audit loop, bounded by your Directive and pausable for the Chairman's Review.
  * *Discovery Mode:* analyzes upstream research and proposes the pages your wiki is missing.
  * *Audit Mode:* pick a page and the Council attacks it — against new evidence, its own revision history, and semantic drift — then outputs a proposed rewrite.
  * Media Readers wired into a Council are distilled once into a compact, machine-verified **Evidence Pack** — key facts plus verbatim quotes with true timestamps — so the full transcript never bloats the adversarial loop. The experts argue interpretation; the evidence is settled before the doors open.

---

## 🎬 The Media-to-Wiki Pipeline

SRT transcripts are now first-class citizens in Nodeleaf. Ask Nodeleaf to compress them and provide a short, on-paper edit of the most impactful statements.
```
                    ┌──────────────────┐
                    │ 🎬 Media Reader  │  (SRT transcript from Redleaf)
                    └────────┬─────────┘
              ┌──────────────┴──────────────┐
    ┌─────────▼─────────┐           ┌─────────▼─────────┐
    │ 🎞️ Media Compressor│         │ 🏛️ Wiki Council    │
    │  (paper edit +     │         │  (debates a verified│
    │    linked audio)   │         │   Evidence Pack)   │
    └─────────┬─────────┘           └─────────┬─────────┘
              └──────────────┬──────────────┘
                    ┌────────▼─────────┐
                    │ 🖋️ Wiki Writer   │  (page with [Doc X @ HH:MM:SS] cites)
                    └──────────────────┘
```

Wiki Council has now been upgraded to understand and provide the same comparative analysis of transcripts. It can also debate and identify the most meaningful aspects of a transcript.

## 🚀 Getting Started

### Prerequisites

1. **[Redleaf](https://github.com/nathanfx330/redleaf)** — running on your local machine or LAN, **with documents ingested**. This is not optional; it is the knowledge engine Node Leaf exists to drive. Set it up first.
2. **[Flutter SDK](https://docs.flutter.dev/get-started/install)** (Version 3.0+)
3. **[Ollama](https://ollama.com/)** with your preferred models (e.g., `gemma3:12b`, `llama3`).
4. *(Optional)* **ffmpeg** (for `ffplay`) or **mpv** — enables in-canvas audition playback. Node Leaf shells out to whichever it finds; no Flutter audio plugins required.

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/nathanfx330/node_leaf.git
   cd node_leaf
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Run the app (Desktop highly recommended):
   ```bash
   flutter run -d macos   # or windows, linux
   ```

---

## ⚙️ Configuration & Connection

On first launch, click the **Settings (⚙️)** icon in the top right.

1. **Connect to Redleaf:** Enter your Redleaf Flask API URL (e.g., `http://127.0.0.1:5000`) with your Redleaf admin username and password, then "Connect & Save".
2. **Connect to Ollama:** Enter your Ollama URL (e.g., `http://127.0.0.1:11434`).

> 💡 **LAN Setup Tip:** If Ollama runs on a different machine than Node Leaf, the host must run Ollama with `OLLAMA_HOST=0.0.0.0` to accept external connections.

---

## ⌨️ Keyboard Shortcuts

* **Delete / Backspace:** Delete selected nodes
* **Ctrl/Cmd + C:** Copy selected node
* **Ctrl/Cmd + V:** Paste node
* **Ctrl/Cmd + Z:** Undo
* **Ctrl/Cmd + S:** Save Project
* **Ctrl/Cmd + Shift + S:** Save Project As
* **Ctrl/Cmd + O:** Open Project
* **Shift + Click:** Add to current selection
* **Shift + Drag Node over Wire:** Insert node into an existing connection

---

## 📄 License

This project is licensed under the MIT License.

**MIT License**

Copyright (c) 2026 Nathaniel Westveer

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.