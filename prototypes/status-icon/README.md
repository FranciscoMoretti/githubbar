# Status icon carve prototype

Question: how can GitHubBar keep a full-size pull-request mark while making real two-digit Review counts readable in an 18×18-point menu-bar icon?

Verdict: **C — Open corner carve**. The pull-request silhouette keeps the full square footprint, its lower-right pixels are cleared through the outer edges, and the count is drawn inside that notch. Counts display exactly through `99` and visually cap there.

Run `./run.sh` to regenerate `status-icon-variants.png`.

The validated result was rewritten for AppKit and folded into production in commit `207d5b8`.
