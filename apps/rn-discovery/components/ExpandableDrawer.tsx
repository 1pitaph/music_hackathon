import { useEffect } from 'react';
import { Pressable, StyleSheet, View } from 'react-native';
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

const DRAWER_MAX = 360;

export function ExpandableDrawer({ station, expanded, onToggle }: Props) {
  const drawerH = useSharedValue(0);

  useEffect(() => {
    if (expanded) {
      drawerH.value = withTiming(DRAWER_MAX, { duration: 320 });
    } else {
      drawerH.value = withTiming(0, { duration: 280 });
    }
  }, [expanded]);

  const drawerAS = useAnimatedStyle(() => ({
    maxHeight: drawerH.value,
    opacity: drawerH.value > 10 ? 1 : 0,
  }));

  const maskAS = useAnimatedStyle(() => ({
    opacity: drawerH.value > 10 ? 1 : 0,
    pointerEvents: drawerH.value > 10 ? ('auto' as const) : ('none' as const),
  }));

  return (
    <View style={styles.outer}>
      <Animated.View style={[styles.mask, maskAS]}>
        <Pressable onPress={onToggle} style={StyleSheet.absoluteFill} />
      </Animated.View>

      <Animated.View style={[styles.drawer, drawerAS]}>
        <View style={styles.sec}>
          <ThemedText style={styles.secLabel}>关于此电台</ThemedText>
          <ThemedText style={styles.desc}>{station.description || '暂无介绍'}</ThemedText>
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
