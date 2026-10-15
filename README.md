# GitHub PRs for Omarchy

A bar widget for the [Omarchy](https://omarchy.org) shell: every pull request
you have open on GitHub, whether its checks pass, and one click to open it.

![The panel open under the bar, listing open PRs grouped by owner with a coloured dot and a status for each](assets/screenshot.png)

## What it shows

The bar shows a pull-request icon and a badge: by default, how many of your
non-draft PRs have failing checks. The badge is red when something counted is
failing, yellow when it is only counting checks still running, and gone when
there is nothing to count. The tooltip spells out the totals.

The panel lists every open PR, grouped by the org or user that owns the
repository. Each row has:

- **A dot** for the head commit's checks:
  - **green**: every check finished and passed (success, neutral or skipped)
  - **yellow**: something is still queued, pending or in progress
  - **red**: something failed, was cancelled, timed out, or needs approval to run
  - **grey**: no checks at all
- **The title**, elided to fit, with the repository and number under it.
- **A status** on the right: `passing`, `running 3/12` (finished of total),
  `failing 2`, or `no checks`; and under it the review decision when there is
  one: `approved`, `changes requested` or `review required`.

Red wins over yellow: one failed check decides a PR, however many are still
going. Drafts are drawn dimmed and sort to the bottom of their group; within a
group, failing PRs come first, then running, passing and unchecked, newest
first.

## Using it

- **Click a row** (or `Enter`, or `o`) to open the PR in your browser.
- **Up and down** move through the PRs, skipping the owner headings.
- **`r`** refreshes, and so does a middle click on the bar button.

The list refreshes every 60 seconds and whenever the panel opens. With a
hundred-odd PRs a refresh takes several seconds; the panel shows what it had
until the new list arrives.

When GitHub cannot be reached, or `gh` is not signed in, the last good list
stays on screen with one line in red above it saying why and how old the list
is. Nothing pops up and nothing is retried faster than the normal interval.

## Settings

Set these on the widget's entry in `~/.config/omarchy/shell.json`, or from the
shell's settings panel:

| Key           | Default   | Meaning |
|---------------|-----------|---------|
| `badge`       | `failing` | What the badge counts: `failing`, `active` (failing and running) or `none` |
| `badgeDrafts` | `false`   | Count draft PRs in the badge too |
| `interval`    | `60`      | Seconds between refreshes (at least 30) |
| `query`       | blank     | A GitHub search to use instead of `is:pr is:open author:@me archived:false` |

```json
{ "id": "travisjeffery.gh-prs", "badge": "active", "interval": 120 }
```

`query` takes anything GitHub's search box does, so `is:pr is:open
review-requested:@me` turns the widget into a review queue.

## How it works

`bin/gh-prs list` runs one GitHub GraphQL search through your existing `gh`
login and prints the JSON the panel draws. Each PR's checks come from its head
commit's status rollup as counts per state, so a PR with eighty checks costs no
more than one with two. Results come 50 to a page: a full page of 100 runs
close to GitHub's ten-second limit and fails often enough to notice.

Nothing in the plugin holds a token. Titles and names from GitHub are drawn as
plain text, and only `https://<host>/<owner>/<repo>/pull/<n>` URLs are handed
to `xdg-open`.

## Installing it

Needs `gh` (signed in with `gh auth login`), `jq` and `xdg-open` on `$PATH`.

```bash
git clone <this repository> ~/src/omarchy-gh-prs
ln -s ~/src/omarchy-gh-prs ~/.config/omarchy/plugins/travisjeffery.gh-prs
omarchy-shell shell rescanPlugins
omarchy plugin enable travisjeffery.gh-prs --section right
```

Once the repository is published, `omarchy plugin add <git-url> --enable`
does the same in one step.

## Screenshots

The data script has a demo mode, so a screenshot never carries real PR titles:

```bash
bin/gh-prs demo on
# ... open the panel, take the screenshot ...
bin/gh-prs demo off
```

## Removing it

```bash
omarchy plugin disable travisjeffery.gh-prs
rm ~/.config/omarchy/plugins/travisjeffery.gh-prs
```
