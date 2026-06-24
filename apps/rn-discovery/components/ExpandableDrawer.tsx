import { useCallback, useEffect, useState } from 'react';
import { LayoutChangeEvent, Pressable, StyleSheet, View } from 'react-native';
import Animated, {
  useAnimatedStyle,
  useSharedValue,
  withTiming,
} from 'react-native-reanimated';

import { IconSymbol } from '@/components/ui/icon-symbol';
import { ThemedText } from '@/components/themed-text';
import { AppleColors, AppleType, Spacing } from '@/constants/theme';
import { Station } from '@/types/station';

interface Props {
  station: Station;
  expanded: boolean;
  onToggle: () => void;
}

/**
 * 抽屉展开 — onLayout 实测内容高度，精确匹配，不留空白。
 * 歌曲最多 5 首，简介最多 300 字。
 */
export function ExpandableDrawer({ station, expanded, onToggle }: Props) {
  const [contentH, setContentH] = useState(0);
  const drawerH = useSharedValue(0);

  // 切换电台 → 重置测量值，避免闪烁
  useEffect(() => {
    setContentH(0);
  }, [station.id]);

  // 测量内容高度 — 无条件更新（变大变小都覆盖）
  const onLayout = useCallback((e: LayoutChangeEvent) => {
    const h = e.nativeEvent.layout.height;
    if (h > 0) setContentH(h);
  }, []);

  useEffect(() => {
    if (expanded && contentH > 0) {
      drawerH.value = withTiming(contentH, { duration: 320 });
    } else {
      drawerH.value = withTiming(0, { duration: 280 });
    }
  }, [expanded, contentH]);

  const drawerAS = useAnimatedStyle(() => ({
    maxHeight: drawerH.value,
    opacity: drawerH.value > 10 ? 1 : 0,
  }));

  const maskAS = useAnimatedStyle(() => ({
    opacity: drawerH.value > 10 ? 1 : 0,
    pointerEvents: drawerH.value > 10 ? ('auto' as const) : ('none' as const),
  }));

  const desc = station.description
    ? station.description.length > 300
      ? station.description.slice(0, 300) + '…'
      : station.description
    : '暂无介绍';

  return (
    <View style={styles.outer}>
      <Animated.View style={[styles.mask, maskAS]}>
        <Pressable onPress={onToggle} style={StyleSheet.absoluteFill} />
      </Animated.View>

      <Animated.View style={[styles.drawer, drawerAS]}>
        {/* 测量层：onLayout 获取实际内容像素高度 */}
        <View onLayout={onLayout}>
          <View style={styles.sec}>
            <ThemedText style={styles.secLabel}>关于此电台</ThemedText>
            <ThemedText style={styles.desc}>{desc}</ThemedText>
          </View>
          {station.songs.length > 0 && (
            <View style={styles.sec}>
              {station.songs.slice(0, 5).map((s) => (
                <View key={s.id} style={styles.songRow}>
                  <IconSymbol size={13} name="music.note.list" color="rgba(255,255,255,0.4)" />
                  <ThemedText style={styles.songTitle} numberOfLines={1}>{s.title}</ThemedText>
                </View>
              ))}
            </View>
          )}
        </View>
      </Animated.View>
    </View>
  );
}

const styles = StyleSheet.create({
  outer: { position: 'relative', zIndex: 10 },

  mask: {
    position: 'absolute',
    top: 0, left: -24, right: -24, bottom: -400,
    backgroundColor: 'rgba(0,0,0,0.5)',
  },

  drawer: {
    backgroundColor: AppleColors.surface,
    overflow: 'hidden',
    borderBottomLeftRadius: 22,
    borderBottomRightRadius: 22,
  },

  sec: {
    paddingHorizontal: Spacing.xl,
    paddingBottom: Spacing.sm,
  },

  secLabel: {
    fontSize: 16, fontWeight: '500' as const,
    color: 'rgba(255,255,255,0.55)',
    letterSpacing: 0.04,
    marginBottom: Spacing.sm,
    paddingTop: Spacing.md,
  },

  desc: {
    fontSize: 14, lineHeight: 22,
    color: 'rgba(255,255,255,0.85)',
  },

  songRow: {
    flexDirection: 'row', alignItems: 'center',
    gap: Spacing.md, paddingVertical: 7,
  },

  songTitle: {
    fontSize: 14, lineHeight: 20,
    fontWeight: '400' as const,
    color: 'rgba(255,255,255,0.88)',
    flex: 1,
  },
});
