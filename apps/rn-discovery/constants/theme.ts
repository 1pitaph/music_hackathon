import { Platform } from 'react-native';

const tintColorLight = '#007AFF';
const tintColorDark = '#0A84FF';

export const Colors = {
  light: { text: '#000000', background: '#FFFFFF', tint: tintColorLight, icon: '#8E8E93', tabIconDefault: '#8E8E93', tabIconSelected: tintColorLight },
  dark:  { text: '#FFFFFF', background: '#000000', tint: tintColorDark,  icon: '#8E8E93', tabIconDefault: '#8E8E93', tabIconSelected: tintColorDark },
};

/** Discover 暗色色板 — near-black #15120F */
export const AppleColors = {
  background: '#15120F',
  surface: '#1E1B18',
  elevated: '#26221E',
  label: '#F5F0E8',
  secondaryLabel: 'rgba(245,240,232,0.60)',
  tertiaryLabel: 'rgba(245,240,232,0.35)',
  quaternaryLabel: 'rgba(245,240,232,0.18)',
  separator: 'rgba(245,240,232,0.10)',
  opaqueSeparator: '#2E2B27',
  accent: '#D9523A',
  accentGlow: 'rgba(217,82,58,0.25)',
  systemFill: 'rgba(245,240,232,0.08)',
} as const;

export const Spacing = {
  xs: 4, sm: 8, md: 12, lg: 16, xl: 20, xxl: 24, xxxl: 32, xxxxl: 48,
  touch: 44,
} as const;

/** iOS 调优字号 */
export const AppleType = {
  largeTitle:  { fontSize: 30, lineHeight: 37, fontWeight: '700' as const, letterSpacing: 0.01 },
  title1:      { fontSize: 26, lineHeight: 33, fontWeight: '600' as const },
  title2:      { fontSize: 22, lineHeight: 28, fontWeight: '600' as const, letterSpacing: -0.01 },
  title3:      { fontSize: 18, lineHeight: 24, fontWeight: '500' as const },
  headline:    { fontSize: 17, lineHeight: 22, fontWeight: '600' as const },
  body:        { fontSize: 17, lineHeight: 22, fontWeight: '400' as const },
  callout:     { fontSize: 16, lineHeight: 21, fontWeight: '400' as const },
  subhead:     { fontSize: 15, lineHeight: 20, fontWeight: '400' as const },
  footnote:    { fontSize: 13, lineHeight: 18, fontWeight: '400' as const },
  caption1:    { fontSize: 12, lineHeight: 16, fontWeight: '400' as const },
  caption2:    { fontSize: 11, lineHeight: 13, fontWeight: '400' as const },
} as const;

/** 统一圆角 */
export const AppleRadius = {
  card: 24,
  player: 22,
  item: 14,
  thumb: 8,
  full: 9999,
} as const;

export const Fonts = Platform.select({
  ios:     { sans: 'system-ui', serif: 'ui-serif', rounded: 'ui-rounded', mono: 'ui-monospace' },
  default: { sans: 'normal', serif: 'serif', rounded: 'normal', mono: 'monospace' },
  web:     { sans: "-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', sans-serif", serif: "Georgia, 'Times New Roman', serif", rounded: "-apple-system, BlinkMacSystemFont, 'SF Pro Rounded', 'Helvetica Neue', sans-serif", mono: "'SF Mono', SFMono-Regular, Menlo, Monaco, Consolas, monospace" },
});
