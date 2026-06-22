import { useEffect, useState } from 'react';
import { ActivityIndicator, Pressable, StyleSheet, View } from 'react-native';
import { ScrollView } from 'react-native-gesture-handler';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { CardStack } from '@/components/CardStack';
import { EmptyState } from '@/components/EmptyState';
import { FloatingPlayer } from '@/components/FloatingPlayer';
import { IconSymbol } from '@/components/ui/icon-symbol';
import { NowPlaying } from '@/components/NowPlaying';
import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import { AppleColors, AppleType, Spacing } from '@/constants/theme';
import { FALLBACK_STATION, STATION_COLORS } from '@/data/stations';
import { loadStations, FetchStationsResult } from '@/services/stationService';
import { Station } from '@/types/station';

export default function DiscoverScreen() {
  const [cardIdx, setCardIdx] = useState(0);
  const [playing, setPlaying] = useState(false);
  const [playingStation, setPlayingStation] = useState<Station | null>(null);
  const [showNowPlaying, setShowNowPlaying] = useState(false);
  const [seekProgress, setSeekProgress] = useState(0);
  const [favIds, setFavIds] = useState<Set<string>>(new Set());

  // ── 数据加载状态 ──
  const [data, setData] = useState<FetchStationsResult | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const insets = useSafeAreaInsets();

  // 加载电台数据（mock 或 API，由 config/index.ts 控制）
  useEffect(() => {
    let cancelled = false;
    loadStations()
      .then((result) => { if (!cancelled) { setData(result); setLoading(false); } })
      .catch((e) => { if (!cancelled) { setError(e?.message ?? '加载失败'); setLoading(false); } });
    return () => { cancelled = true; };
  }, []);

  const allStations = data?.stations ?? [];
  const cardStations = data
    ? data.randomIds.map((id) => allStations.find((s) => s.id === id)).filter(Boolean) as Station[]
    : [];

  const has = cardStations.length > 0;
  const cur = has ? cardStations[cardIdx] : null;
  const cardIsPlaying = playing && playingStation?.id === cur?.id;
  const startStation = (s: Station) => {
    setPlayingStation(s);
    setSeekProgress(0);
    setPlaying(true);
  };

  // ── 卡片区 ──
  const goCardPrev = () => setCardIdx(i => (i - 1 + cardStations.length) % cardStations.length);
  const goCardNext = () => setCardIdx(i => (i + 1) % cardStations.length);
  const handleCardToggle = () => {
    if (!cur) return;
    if (playingStation?.id === cur.id) { setPlaying(p => !p); }
    else { startStation(cur); }
  };

  // ── 悬浮播放栏 (station 级切换) ──
  const goPlayerPrev = () => {
    if (!playingStation) return;
    const idx = allStations.findIndex(s => s.id === playingStation.id);
    startStation(allStations[(idx - 1 + allStations.length) % allStations.length]);
  };
  const goPlayerNext = () => {
    if (!playingStation) return;
    const idx = allStations.findIndex(s => s.id === playingStation.id);
    startStation(allStations[(idx + 1) % allStations.length]);
  };

  const handleSeek = (p: number) => setSeekProgress(p);

  // ── 收藏 ──
  const toggleFav = (stationId: string) => {
    setFavIds(prev => {
      const next = new Set(prev);
      if (next.has(stationId)) next.delete(stationId); else next.add(stationId);
      return next;
    });
  };

  const showPlayer = playingStation !== null;

  // ── 加载中 ──
  if (loading) {
    return (
      <ThemedView style={[styles.root, { paddingTop: insets.top }]} lightColor={AppleColors.background} darkColor={AppleColors.background}>
        <View style={styles.center}>
          <ActivityIndicator size="small" color={AppleColors.accent} />
        </View>
      </ThemedView>
    );
  }

  // ── 加载失败 ──
  if (error || !data) {
    return (
      <ThemedView style={[styles.root, { paddingTop: insets.top }]} lightColor={AppleColors.background} darkColor={AppleColors.background}>
        <View style={styles.ew}>
          <EmptyState
            isPlaying={playing}
            onPlayToggle={() => {
              if (!playing) { startStation(FALLBACK_STATION); }
              else { setPlaying(false); }
            }}
          />
        </View>
      </ThemedView>
    );
  }

  return (
    <ThemedView style={[styles.root, { paddingTop: insets.top }]} lightColor={AppleColors.background} darkColor={AppleColors.background}>
      <ScrollView contentContainerStyle={[styles.sc, { paddingBottom: insets.bottom + 20 }]} showsVerticalScrollIndicator={false}>
        {/* ── Header：左图标 + 居中标题 + 右图标 ── */}
        <View style={styles.hd}>
          <Pressable style={styles.hdIcon} hitSlop={8}>
            <IconSymbol size={24} name="magnifyingglass" color={AppleColors.secondaryLabel} />
          </Pressable>

          <View style={styles.hdTitle}>
            <ThemedText style={styles.pt} lightColor={AppleColors.label} darkColor={AppleColors.label}>发现</ThemedText>
          </View>

          <Pressable style={styles.hdIcon} hitSlop={8}>
            <IconSymbol size={24} name="bell" color={AppleColors.secondaryLabel} />
          </Pressable>
        </View>

        {has ? (
          <CardStack
            stations={cardStations}
            currentIndex={cardIdx}
            isPlaying={cardIsPlaying}
            onPlayToggle={handleCardToggle}
            onPrev={goCardPrev}
            onNext={goCardNext}
          />
        ) : (
          <View style={styles.ew}>
            <EmptyState
              isPlaying={playing}
              onPlayToggle={() => {
                if (!playing) { startStation(FALLBACK_STATION); }
                else { setPlaying(false); }
              }}
            />
          </View>
        )}

      </ScrollView>

      {/* 悬浮播放栏 */}
      {showPlayer && playingStation && (
        <FloatingPlayer
          title={playingStation.title}
          host={playingStation.hostName}
          songTitle={playingStation.title}
          color={STATION_COLORS[playingStation.id] ?? '#8C7355'}
          isPlaying={playing}
          onPlayToggle={() => setPlaying(p => !p)}
          onPrev={goPlayerPrev}
          onNext={goPlayerNext}
          onExpandPlayer={() => setShowNowPlaying(true)}
        />
      )}

      {/* 全屏播放器 */}
      {playingStation && (
        <NowPlaying
          visible={showNowPlaying}
          station={playingStation}
          isPlaying={playing}
          progress={seekProgress}
          isFavorited={favIds.has(playingStation.id)}
          onClose={() => setShowNowPlaying(false)}
          onTogglePlay={() => setPlaying(p => !p)}
          onPrevStation={goPlayerPrev}
          onNextStation={goPlayerNext}
          onSeek={handleSeek}
          onToggleFavorite={() => toggleFav(playingStation.id)}
        />
      )}
    </ThemedView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  sc: {},
  hd: {
    flexDirection: 'row', alignItems: 'center',
    paddingHorizontal: 8, paddingTop: 12, paddingBottom: Spacing.xxl,
  },
  hdIcon: { width: 44, height: 44, alignItems: 'center', justifyContent: 'center' },
  hdTitle: { flex: 1, alignItems: 'center' },
  pt: { fontSize: 30, fontWeight: '700' as const, lineHeight: 36, letterSpacing: 0.02 },
  ew: { paddingHorizontal: Spacing.lg, paddingVertical: Spacing.xxxl },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
});
