# Status icon alternatives

Research scope: official GitHub Primer/Octicons assets, GitHub brand guidance, and Apple platform guidance for GitHubBar's 18×18 menu-bar status item. The design constraint is an open lower-right carve containing a one- or two-digit review count.

## Platform and source constraints

- Primer says Octicons are available at designated 12, 16, and 24 px sizes and should not be resized because the paths are tuned for legibility. For an 18×18 status canvas, use the official 16 px path centered rather than scaling a 16 px asset to 18 px. [Primer Octicons usage guidelines](https://primer.style/octicons/usage-guidelines/)
- Apple provides a square status-item length equal to the menu-bar thickness, and its template-image model expects black plus transparency so the system can adapt the artwork to its state. This supports a single monochrome silhouette plus transparent carve. [NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem) · [NSImage.isTemplate](https://developer.apple.com/documentation/appkit/nsimage/istemplate)
- GitHub's Octicons repository identifies the icons as GitHub-built and applies its MIT code license to non-logo files, while directing logo usage to the separate brand rules. [Primer Octicons repository](https://github.com/primer/octicons)

## Candidate assessment

| Official icon | What it communicates | Lower-right carve at 16 px | Verdict |
| --- | --- | --- | --- |
| [`code-review`](https://github.com/primer/octicons/blob/main/icons/code-review-16.svg) | Code review and discussion; the closest semantic match to the app's primary action | **Good.** The code chevrons and most of the speech-bubble frame remain. The carve removes only the lower-right frame; the speech tail is safely on the lower left. It is denser than the current PR mark, so test its inner detail at 1×. | **Prototype.** Best semantic alternative. |
| [`repo`](https://github.com/primer/octicons/blob/main/icons/repo-16.svg) | GitHub repositories, which are the app's filter and scope | **Good.** The book spine, top edge, and page block survive. Start the carve to the right of the centered bookmark so the lower-right edge becomes the intentional open corner. | **Prototype.** Strong silhouette, but describes the source more than the review inbox. |
| [`stack`](https://github.com/primer/octicons/blob/main/icons/stack-16.svg) | A queue or aggregated stack of work across repositories | **Fair to good.** The upper diamond remains recognizable, but the carve shortens the lower two layers asymmetrically. It needs pixel-level tuning so the layers do not look accidentally broken. | **Prototype.** Best metaphor for high volume and aggregation. |
| [`workflow`](https://github.com/primer/octicons/blob/main/icons/workflow-16.svg) | A connected development workflow | **Poor.** Its defining destination node occupies the lower-right quadrant, exactly where the count must go. Removing it leaves a bent connector rather than a workflow. | Reject for this count construction. |
| [`checklist`](https://github.com/primer/octicons/blob/main/icons/checklist-16.svg) | Actionable review queue / tasks to complete | **Poor.** The checkmark is in the lower-right quadrant. The carve removes the part that distinguishes this from a generic document. | Reject for this count construction. |
| [`mark-github`](https://github.com/primer/octicons/blob/main/icons/mark-github-16.svg) | Immediate recognition of GitHub as the connected service | **Technically poor and legally unsuitable.** A lower-right carve materially alters the solid circular Invertocat silhouette. More importantly, GitHub says third parties must not use a GitHub logo as their offering/project icon and must not modify the logo. | Do not prototype as the app/status icon. |

The GitHub mark can only be considered as an unmodified secondary integration indicator, not as GitHubBar's carved status icon. GitHub permits secondary use to indicate an integration, but disallows using the mark as the offering's logo or altering it. [GitHub Brand Toolkit: Logo](https://brand.github.com/foundations/logo) · [GitHub Logo Policy](https://docs.github.com/en/site-policy/other-site-policies/github-logo-policy)

## Recommended prototype set

1. **`code-review`** — strongest match to “items awaiting my review,” with a carve that preserves its semantic core.
2. **`repo`** — clearest simple GitHub-domain object after excluding the protected GitHub mark.
3. **`stack`** — most distinctive expression of GitHubBar's high-throughput aggregation value.

Render all three from the official 16 px paths, centered without geometric scaling in the same 18×18 template canvas, using the identical carve and sample counts `2`, `20`, and `99`. Evaluate them at actual 1× menu-bar size; enlarged previews alone will conceal stroke and counter failures.
