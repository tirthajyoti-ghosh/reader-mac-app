# Retrieval findings

The retrieval study draws on the [Stanford long-context benchmark](https://example.com/lost-in-the-middle) and the follow-up replication, both of which report the same degradation curve. Our internal write-up lives in [links-target.md](links-target.md), and the methodology mirrors what we set out earlier under [§ Evaluation harness](#evaluation-harness). An [earlier post we already read](https://example.org/old-post) is here too.

## Background

A link is a detour, not a destination. Hover a link to peek; click an external one for a slide-over that leaves this doc exactly where it was. ⌥-click (or drag the sheet wider) escalates to a split; ⌘-click opens the system browser. Internal `.md` links open in place with a breadcrumb Back.

## Evaluation harness

We sample 500 needle-in-haystack prompts per context length and measure exact-match recall. Each run is seeded so the results are reproducible bit-for-bit. The headline finding — recall collapses past 32k tokens — has now been reproduced three times across independent labs.

Jump back up to the [§ Background](#background) to re-read the gestures.

## Methodology

Write every probe to both stores. We verify parity with the `drift-check` job before advancing. See the live dashboard at [http://localhost:3000](http://localhost:3000) during a run.

## A longer section to enable scrolling

Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.

Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.

Sed ut perspiciatis unde omnis iste natus error sit voluptatem accusantium doloremque laudantium, totam rem aperiam, eaque ipsa quae ab illo inventore veritatis et quasi architecto beatae vitae dicta sunt explicabo.

Nemo enim ipsam voluptatem quia voluptas sit aspernatur aut odit aut fugit, sed quia consequuntur magni dolores eos qui ratione voluptatem sequi nesciunt.
