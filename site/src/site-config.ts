import type { SiteConfig } from '@mcptoolshop/site-theme';

export const config: SiteConfig = {
  title: 'AI RPG Stage',
  description: 'Godot 4 client for AI RPG Engine. Renders a sim it does not own.',
  logoBadge: 'ST',
  brandName: 'AI RPG Stage',
  repoUrl: 'https://github.com/mcp-tool-shop-org/ai-rpg-stage',
  footerText: 'MIT Licensed — built by <a href="https://mcp-tool-shop.github.io/" style="color:var(--color-muted);text-decoration:underline">MCP Tool Shop</a>',

  hero: {
    badge: 'Godot 4.7 · open source',
    headline: 'A client that decides nothing.',
    headlineAccent: 'The simulation is the truth.',
    description:
      'AI RPG Stage attaches to a running AI RPG Engine over JSON-RPC, submits what the player is trying to do, and draws what comes back. It holds no rules, advances no clock, and says so out loud when it disagrees with the sim. The play camera is a 2:1 dimetric harbour: Y-sorted buildings, Foundry HD characters, torches on normal maps, town art that passed a projection gate.',
    primaryCta: { href: 'https://github.com/mcp-tool-shop-org/ai-rpg-stage', label: 'View on GitHub' },
    secondaryCta: { href: 'handbook/', label: 'Read the Handbook' },
    previews: [
      { label: 'Play', code: 'node tools/play.mjs' },
      { label: 'Test', code: './verify.sh' },
      { label: 'One suite', code: 'godot --headless --path . --script res://tools/headless.gd -- --only=iso_world' },
    ],
  },

  sections: [
    {
      kind: 'features',
      id: 'features',
      title: 'What it is',
      subtitle: 'A rendering surface for a deterministic simulation, arranged so it cannot become a second truth.',
      features: [
        {
          title: 'Decides nothing',
          desc: 'Occupancy is a zone id in the engine. The stage submits intent, renders events, and on a hash mismatch reports it and re-snapshots. It never patches the sim.',
        },
        {
          title: '2:1 dimetric harbour',
          desc: 'One TileMapLayer, 256×128 diamonds, Y-sorted. Buildings sliced into 128 px strips so every diamond has one drawable. Contact blobs under every actor.',
        },
        {
          title: 'Gated art',
          desc: 'Every plate was rendered through a Blender camera at X 60° / Z 45° and must pass a ten-check ANDON before it is loaded. Wrong projection, no alpha, baked backdrop: refused.',
        },
        {
          title: 'Felt audio',
          desc: 'The handshake asks for capabilities.audio. Zone stems, overlay stings that do not kill the stem, the spoken line once, camera trauma from the same payload. Never hashed.',
        },
        {
          title: 'Proofs with controls',
          desc: 'Eleven headless suites, each with a fixture or control that makes it fail. A test that asserts nothing fails. A filter that matches nothing fails.',
        },
        {
          title: 'One outbound socket',
          desc: 'No default endpoint, no discovery, no listener, no credentials, no telemetry. The trust boundary is the engine you point it at.',
        },
      ],
    },
    {
      kind: 'code-cards',
      id: 'usage',
      title: 'Usage',
      cards: [
        {
          title: 'Play Salt Road',
          code: '# Godot 4.7 on PATH, engine built as a sibling (../ai-rpg-engine)\nnode tools/play.mjs\n\n# options\nnode tools/play.mjs --seed 71 --port 47820 --no-shock\nnode tools/play.mjs --headless   # start the sim only, print the port',
        },
        {
          title: 'Run the suite',
          code: './verify.sh\n\n# by hand\ngodot --headless --path . --import\ngodot --headless --path . --script res://tools/headless.gd\ngodot --headless --path . --script res://tools/headless.gd -- --only=scene_join',
        },
        {
          title: 'Gate a plate',
          code: 'python assets/dimetric/andon/iso_andon.py assets/dimetric/ground/dirt_a.png --kind ground\npython assets/dimetric/andon/iso_andon.py assets/dimetric/structures/shed_2x2/beauty.png --kind structure --footprint 2,2\n# exit 0 only when every gate passes',
        },
        {
          title: 'Attach by hand',
          code: '# a sidecar you started yourself\ngodot --path . -- --attach=127.0.0.1:47820\n\n# the stage requests capabilities.hashes + capabilities.audio\n# and reports [stale] ... when the sim disagrees',
        },
      ],
    },
  ],
};
