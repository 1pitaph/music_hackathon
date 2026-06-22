import { StyleSheet, View } from 'react-native';
import Animated, { useAnimatedStyle, useSharedValue, withSpring, withTiming } from 'react-native-reanimated';
import { Pressable } from 'react-native-gesture-handler';

import { IconSymbol } from '@/components/ui/icon-symbol';
import { ThemedText } from '@/components/themed-text';
import { AppleColors, AppleRadius, AppleType, Spacing } from '@/constants/theme';
import { Station } from '@/types/station';

interface Props { station: Station; expanded: boolean; onToggle: () => void; }

export function ExpandableDrawer({ station, expanded, onToggle }: Props) {
  const h = useSharedValue(0);
  const rot = useSharedValue(0);
  const dA = useAnimatedStyle(() => ({ maxHeight: h.value, opacity: h.value > 10 ? 1 : 0 }));
  const cA = useAnimatedStyle(() => ({ transform: [{ rotate: `${rot.value}deg` }] }));

  const tg = () => {
    if (expanded) {
      h.value = withTiming(0, { duration: 200 });
      rot.value = withSpring(0, { damping: 12, stiffness: 160 });
    } else {
      h.value = withSpring(500, { damping: 14, stiffness: 140 });
      rot.value = withSpring(180, { damping: 12, stiffness: 160 });
    }
    onToggle();
  };

  return (
    <View>
      <Pressable onPress={tg} style={styles.hd}>
        <ThemedText style={styles.hl} lightColor={AppleColors.quaternaryLabel} darkColor={AppleColors.quaternaryLabel}>
          说明与歌单
        </ThemedText>
        <Animated.View style={cA}>
          <IconSymbol size={14} name="chevron.down" color={AppleColors.tertiaryLabel} />
        </Animated.View>
      </Pressable>

      <Animated.View style={[styles.dr, dA]}>
        {/* 关于此电台 — 使用 description 字段 */}
        <View style={styles.sc}>
          <ThemedText style={styles.st} lightColor={AppleColors.tertiaryLabel} darkColor={AppleColors.tertiaryLabel}>关于此电台</ThemedText>
          <ThemedText style={styles.ds} lightColor={AppleColors.secondaryLabel} darkColor={AppleColors.secondaryLabel}>
            {station.description || '暂无介绍'}
          </ThemedText>
        </View>

        {/* 歌曲列表 */}
        {station.songs.length > 0 && (
          <View style={styles.sc}>
            <ThemedText style={styles.st} lightColor={AppleColors.tertiaryLabel} darkColor={AppleColors.tertiaryLabel}>歌曲列表</ThemedText>
            {station.songs.slice(0, 5).map(s => (
              <View key={s.id} style={styles.sr}>
                <ThemedText style={styles.sn} numberOfLines={1} lightColor={AppleColors.label} darkColor={AppleColors.label}>{s.title}</ThemedText>
                <ThemedText style={styles.sa} numberOfLines={1} lightColor={AppleColors.secondaryLabel} darkColor={AppleColors.secondaryLabel}>{s.artist}</ThemedText>
              </View>
            ))}
            {station.songs.length > 5 && (
              <Pressable style={styles.va}>
                <ThemedText style={styles.vl} lightColor={AppleColors.accent} darkColor={AppleColors.accent}>查看全部</ThemedText>
              </Pressable>
            )}
          </View>
        )}
      </Animated.View>
    </View>
  );
}

const styles = StyleSheet.create({
  hd: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', paddingVertical: Spacing.md, marginHorizontal: 56, gap: 6 },
  hl: { ...AppleType.caption2, letterSpacing: 0.04 },
  dr: { overflow: 'hidden', paddingHorizontal: Spacing.xl, borderBottomLeftRadius: AppleRadius.card, borderBottomRightRadius: AppleRadius.card },
  sc: { paddingBottom: Spacing.lg },
  st: { ...AppleType.caption1, textTransform: 'uppercase', letterSpacing: 0.06, marginBottom: Spacing.sm },
  ds: { ...AppleType.footnote, lineHeight: 22 },
  sr: { flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 8, borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: AppleColors.separator },
  sn: { ...AppleType.callout, flex: 1 },
  sa: { ...AppleType.footnote, marginLeft: Spacing.lg },
  va: { alignSelf: 'flex-start', marginTop: Spacing.md, paddingVertical: Spacing.sm, paddingHorizontal: Spacing.lg, borderRadius: AppleRadius.thumb, borderWidth: 0.5, borderColor: AppleColors.accent },
  vl: { ...AppleType.footnote, fontWeight: '600' },
});
