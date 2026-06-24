import { Image } from 'expo-image';
import { Pressable, StyleSheet, View } from 'react-native';
import Animated, { runOnJS, useAnimatedStyle, useSharedValue, withSequence, withTiming } from 'react-native-reanimated';

import { IconSymbol } from '@/components/ui/icon-symbol';
import { ThemedText } from '@/components/themed-text';
import { AppleColors, AppleRadius, AppleType, Spacing } from '@/constants/theme';
import { COVER_IMAGES } from '@/data/stations';
import { popularStationIds } from '@/data/trending';
import { Station } from '@/types/station';

const COVER = 48;
const AP = Animated.createAnimatedComponent(Pressable);

function fmt(n: number): string {
  return n >= 1000 ? `${(n / 1000).toFixed(1)}k` : `${n}`;
}

interface Props {
  stations: Station[];
  onPlayStation: (s: Station) => void;
}

/** 热门电台列表 — 收藏数 + 风格标签 + 箭头。点击播放，不切卡片。 */
export function HotStationsList({ stations, onPlayStation }: Props) {
  const rows = popularStationIds
    .map((id) => stations.find((s) => s.id === id))
    .filter(Boolean) as Station[];

  return (
    <View style={styles.sc}>
      <ThemedText style={styles.h} lightColor={AppleColors.label} darkColor={AppleColors.label}>
        热门电台
      </ThemedText>

      {rows.map((s, i) => (
        <View key={s.id}>
          <HotListItem station={s} onPress={() => onPlayStation(s)} />
          {i < rows.length - 1 && <View style={styles.dv} />}
        </View>
      ))}

      <View style={styles.btm}>
        <ThemedText style={styles.btt} lightColor={AppleColors.tertiaryLabel} darkColor={AppleColors.tertiaryLabel}>
          滑到底了，要听听自己的电台吗？
        </ThemedText>
      </View>
    </View>
  );
}

/** 单项 — 按压 scale 0.98 + 阴影 */
function HotListItem({ station: s, onPress }: { station: Station; onPress: () => void }) {
  const sc = useSharedValue(1);
  const aS = useAnimatedStyle(() => ({ transform: [{ scale: sc.value }] }));
  const press = () => {
    sc.value = withSequence(
      withTiming(0.97, { duration: 80 }),
      withTiming(1, { duration: 100 }),
    );
    runOnJS(onPress)();
  };

  return (
    <AP onPress={press} style={[styles.r, aS]}>
      <Image source={COVER_IMAGES[s.id]} style={styles.cv} contentFit="cover" />
      <View style={styles.tb}>
        <ThemedText style={styles.n} numberOfLines={1} lightColor={AppleColors.label} darkColor={AppleColors.label}>
          {s.title}
        </ThemedText>
        <View style={styles.meta}>
          <ThemedText style={styles.a} numberOfLines={1} lightColor={AppleColors.secondaryLabel} darkColor={AppleColors.secondaryLabel}>
            {s.hostName}
          </ThemedText>
          <ThemedText style={styles.gen} numberOfLines={1} lightColor={AppleColors.quaternaryLabel} darkColor={AppleColors.quaternaryLabel}>
            · {s.genre}
          </ThemedText>
        </View>
      </View>
      <View style={styles.rt}>
        <ThemedText style={styles.fv} lightColor={AppleColors.quaternaryLabel} darkColor={AppleColors.quaternaryLabel}>
          {fmt(s.favorites)}
        </ThemedText>
        <IconSymbol size={15} name="chevron.right" color={AppleColors.tertiaryLabel} />
      </View>
    </AP>
  );
}

const styles = StyleSheet.create({
  sc: { paddingBottom: 80 },
  h: { ...AppleType.title3, paddingHorizontal: Spacing.xl, paddingTop: Spacing.xxxl, paddingBottom: Spacing.md },
  r: { flexDirection: 'row', alignItems: 'center', paddingVertical: Spacing.md, paddingHorizontal: Spacing.xl, gap: Spacing.md },
  cv: { width: COVER, height: COVER, borderRadius: AppleRadius.thumb },
  tb: { flex: 1, gap: 2 },
  meta: { flexDirection: 'row', alignItems: 'center' },
  n: { ...AppleType.callout },
  a: { ...AppleType.subhead },
  gen: { ...AppleType.caption2, color: AppleColors.quaternaryLabel },
  rt: { flexDirection: 'row', alignItems: 'center', gap: Spacing.sm },
  fv: { ...AppleType.caption1 },
  dv: { height: StyleSheet.hairlineWidth, backgroundColor: AppleColors.separator, marginLeft: Spacing.xl + COVER + Spacing.md, marginRight: Spacing.xl },
  btm: { alignItems: 'center', paddingTop: Spacing.md },
  btt: { ...AppleType.caption2 },
});
