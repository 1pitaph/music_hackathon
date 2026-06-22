import { useState } from 'react';
import { Pressable, StyleSheet, View } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import Animated, { runOnJS, useAnimatedStyle, useSharedValue, withSequence, withSpring } from 'react-native-reanimated';

import { ExpandableDrawer } from '@/components/ExpandableDrawer';
import { ThemedText } from '@/components/themed-text';
import { IconSymbol } from '@/components/ui/icon-symbol';
import { AppleColors, AppleRadius, AppleType, Spacing } from '@/constants/theme';
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
  const aS = useAnimatedStyle(() => ({ transform: [{ scale: sc.value }] }));

  const press = () => {
    if (!isActive) return;
    sc.value = withSequence(withSpring(0.98, { damping: 14, stiffness: 400 }), withSpring(1, { damping: 10, stiffness: 300 }));
    runOnJS(onPlayToggle)();
  };

  const c = STATION_COLORS[station.id] ?? '#8C7355';
  const g = glowHex(c);

  return (
    <View style={[styles.card, isActive && styles.cardSh]}>
      {/* 封面渐变区 */}
      <AP style={[styles.art, aS]} onPress={press}>
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
            <IconSymbol size={19} name={fav ? 'heart.fill' : 'heart'} color={fav ? AppleColors.accent : AppleColors.tertiaryLabel} />
          </Pressable>
        </View>

        {/* briefIntro — 卡片非展开态的一句话简介 */}
        <ThemedText style={styles.desc} numberOfLines={1} lightColor={AppleColors.tertiaryLabel} darkColor={AppleColors.tertiaryLabel}>
          {station.briefIntro}
        </ThemedText>
      </View>

      {/* 抽屉 — 展开后显示 description */}
      {isActive && <ExpandableDrawer station={station} expanded={open} onToggle={() => setOpen(o => !o)} />}
    </View>
  );
}

const styles = StyleSheet.create({
  card: { backgroundColor: AppleColors.surface, borderRadius: AppleRadius.card },
  cardSh: { shadowColor: '#000', shadowOffset: { width: 0, height: 12 }, shadowOpacity: 0.45, shadowRadius: 28, elevation: 16 },
  art: { position: 'relative', height: 310, overflow: 'hidden', borderTopLeftRadius: AppleRadius.card, borderTopRightRadius: AppleRadius.card },
  gr: { ...StyleSheet.absoluteFillObject },
  gl: { position: 'absolute', top: -20, left: -20, right: -20, bottom: -20, borderRadius: 48, opacity: 0.35 },
  glOn: { opacity: 0.65 },
  hl: { position: 'absolute', top: 16, left: '20%', width: '60%', height: '50%', backgroundColor: 'rgba(255,255,255,0.06)', borderRadius: 999, transform: [{ scaleY: 0.4 }] },
  infoBg: { backgroundColor: AppleColors.surface },
  info: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: Spacing.xl, paddingTop: Spacing.lg },
  txt: { flex: 1, gap: 3 },
  tt: { ...AppleType.title2 },
  sh: { ...AppleType.subhead },
  fb: { width: 44, height: 44, alignItems: 'center', justifyContent: 'center' },
  desc: { ...AppleType.footnote, paddingHorizontal: Spacing.xl, paddingBottom: Spacing.lg, paddingTop: Spacing.xs },
});
