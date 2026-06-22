import { useState } from 'react';
import { Pressable, StyleSheet, View } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import Animated, { runOnJS, useAnimatedStyle, useSharedValue, withSequence, withSpring } from 'react-native-reanimated';

import { ExpandableDrawer } from '@/components/ExpandableDrawer';
import { ThemedText } from '@/components/themed-text';
import { IconSymbol } from '@/components/ui/icon-symbol';
import { AppleColors, AppleType, Spacing } from '@/constants/theme';
import { STATION_COLORS } from '@/data/stations';
import { Station } from '@/types/station';

const AP = Animated.createAnimatedComponent(Pressable);

function glowHex(hex: string): string {
  const r = parseInt(hex.slice(1, 3), 16);
  const g = parseInt(hex.slice(3, 5), 16);
  const b = parseInt(hex.slice(5, 7), 16);
  return `rgba(${r},${g},${b},0.28)`;
}

interface Props { station: Station; isActive: boolean; isPlaying: boolean; onPlayToggle: () => void; }

export function StationCard({ station, isActive, isPlaying, onPlayToggle }: Props) {
  const [fav, setFav] = useState(false);
  const [open, setOpen] = useState(false);
  const sc = useSharedValue(1);

  const press = () => {
    if (!isActive) return;
    sc.value = withSequence(withSpring(0.98, { damping: 14, stiffness: 400 }), withSpring(1, { damping: 10, stiffness: 300 }));
    runOnJS(onPlayToggle)();
  };

  const handleToggle = () => setOpen(o => !o);

  const c = STATION_COLORS[station.id] ?? '#8C7355';
  const g = glowHex(c);

  return (
    <View style={[styles.wrap, isActive && styles.wrapActive]}>
      {/* ── 主卡 ── */}
      <View style={styles.main}>
        {/* 封面 */}
        <AP style={styles.art} onPress={press}>
          <View style={[styles.gl, { backgroundColor: g }, isPlaying && styles.glOn]} />
          <LinearGradient colors={[c, c + 'CC', c + '99']} start={{ x: 0.2, y: 0 }} end={{ x: 0.8, y: 1 }} style={styles.gr} />
          <View style={styles.hl} />
        </AP>

        {/* 信息区 */}
        <View style={styles.infoBg}>
          <View style={styles.info}>
            <View style={styles.txt}>
              <ThemedText style={styles.tt} numberOfLines={1} lightColor={AppleColors.label} darkColor={AppleColors.label}>{station.title}</ThemedText>
              <ThemedText style={styles.sh} numberOfLines={1} lightColor={AppleColors.secondaryLabel} darkColor={AppleColors.secondaryLabel}>{station.hostName}</ThemedText>
            </View>
            <Pressable onPress={() => setFav(f => !f)} hitSlop={10} style={({ pressed }) => [styles.fb, pressed && { opacity: 0.5 }]}>
              <IconSymbol size={24} name={fav ? 'heart.fill' : 'heart'} color={fav ? AppleColors.accent : AppleColors.tertiaryLabel} />
            </Pressable>
          </View>

          <ThemedText style={styles.desc} numberOfLines={1} lightColor={AppleColors.tertiaryLabel} darkColor={AppleColors.tertiaryLabel}>
            {station.briefIntro}
          </ThemedText>
        </View>
      </View>

      {/* ── Handle — 点击展开/收起 ── */}
      {isActive && (
        <View style={styles.handleWrap}>
          <Pressable onPress={handleToggle} style={styles.handleBar}>
            <View style={styles.handlePill} />
          </Pressable>
        </View>
      )}

      {/* ── 抽屉 — 向下展开 ── */}
      {isActive && (
        <ExpandableDrawer
          station={station}
          expanded={open}
          onToggle={handleToggle}
        />
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: {
    backgroundColor: '#15120F',
  },
  wrapActive: {
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 25 },
    shadowOpacity: 0.50,
    shadowRadius: 60,
    elevation: 20,
  },

  main: {
    borderRadius: 22,
    overflow: 'hidden',
    backgroundColor: 'rgba(36,34,30,0.78)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.14)',
  },

  art: {
    position: 'relative',
    height: 370,
    overflow: 'hidden',
    borderTopLeftRadius: 22,
    borderTopRightRadius: 22,
  },
  gr: { ...StyleSheet.absoluteFillObject },
  gl: { position: 'absolute', top: -20, left: -20, right: -20, bottom: -20, borderRadius: 48, opacity: 0.35 },
  glOn: { opacity: 0.65 },
  hl: {
    position: 'absolute',
    top: 16, left: '20%', width: '60%', height: '50%',
    backgroundColor: 'rgba(255,255,255,0.06)', borderRadius: 999,
    transform: [{ scaleY: 0.4 }],
  },

  infoBg: { backgroundColor: 'rgba(36,34,30,0.75)' },
  info: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: Spacing.xl, paddingTop: Spacing.lg },
  txt: { flex: 1, gap: 3 },
  tt: { ...AppleType.title2 },
  sh: { ...AppleType.subhead },
  fb: { width: 44, height: 44, alignItems: 'center', justifyContent: 'center' },
  desc: { ...AppleType.footnote, paddingHorizontal: Spacing.xl, paddingBottom: Spacing.sm, paddingTop: Spacing.xs },

  // Handle
  handleWrap: {
    backgroundColor: 'rgba(36,34,30,0.75)',
    paddingBottom: Spacing.md,
    borderBottomLeftRadius: 22,
    borderBottomRightRadius: 22,
  },
  handleBar: {
    alignItems: 'center',
    justifyContent: 'center',
    height: 44,
  },
  handlePill: {
    width: 36,
    height: 4,
    borderRadius: 999,
    backgroundColor: 'rgba(255,255,255,0.42)',
  },
});
