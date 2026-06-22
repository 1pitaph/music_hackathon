import { useEffect, useState } from 'react';
import { ActivityIndicator, StyleSheet, View } from 'react-native';
import { ScrollView } from 'react-native-gesture-handler';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { CardStack } from '@/components/CardStack';
import { EmptyState } from '@/components/EmptyState';
import { FloatingPlayer } from '@/components/FloatingPlayer';
import { HotStationsList } from '@/components/HotStationsList';
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
  const [songIndex, setSongIndex] = useState(0);
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
  const songs = playingStation?.songs ?? [];
  const curSong = songs.length > 0 ? songs[songIndex % songs.length] : null;

  const startStation = (s: Station, fromIdx = 0) => {
    setPlayingStation(s);
    setSongIndex(fromIdx);
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

  // ── 热门列表 ──
  const handlePlayStation = (s: Station) => startStation(s);

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

  // ── 全屏播放器 (song 级切换) ──
  const goPrevSong = () => {
    if (songs.length === 0) return;
    setSongIndex(i => (i - 1 + songs.length) % songs.length);
    setSeekProgress(0);
  };
  const goNextSong = () => {
    if (songs.length === 0) return;
    setSongIndex(i => (i + 1) % songs.length);
    setSeekProgress(0);
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
      <ScrollView contentContainerStyle={[styles.sc, { paddingBottom: insets.bottom + 80 }]} showsVerticalScrollIndicator={false}>
        <View style={styles.hd}>
          <ThemedText style={styles.pt} lightColor={AppleColors.label} darkColor={AppleColors.label}>发现</ThemedText>
          <ThemedText style={styles.sub} lightColor={AppleColors.secondaryLabel} darkColor={AppleColors.secondaryLabel}>discover</ThemedText>
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

        <HotStationsList stations={allStations} onPlayStation={handlePlayStation} />
      </ScrollView>

      {/* 悬浮播放栏 */}
      {showPlayer && playingStation && (
        <FloatingPlayer
          title={playingStation.title}
          host={playingStation.hostName}
          songTitle={curSong?.title}
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
          songIndex={songIndex}
          isPlaying={playing}
          progress={seekProgress}
          isFavorited={favIds.has(playingStation.id)}
          onClose={() => setShowNowPlaying(false)}
          onTogglePlay={() => setPlaying(p => !p)}
          onPrevSong={goPrevSong}
          onNextSong={goNextSong}
          onSeek={handleSeek}
          onToggleFavorite={() => toggleFav(playingStation.id)}
        />
      )}
    </ThemedView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  sc: { flexGrow: 1 },
  hd: { paddingHorizontal: Spacing.xl, paddingTop: 24, paddingBottom: Spacing.md },
  pt: { ...AppleType.largeTitle },
  sub: { ...AppleType.subhead, fontWeight: '500', marginTop: 2 },
  ew: { paddingHorizontal: Spacing.lg, paddingVertical: Spacing.xxxl },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
});
