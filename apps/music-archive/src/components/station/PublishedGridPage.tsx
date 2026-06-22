import React, { useState, useRef } from 'react';
import {
  View,
  Text,
  FlatList,
  TouchableOpacity,
  ScrollView,
  StyleSheet,
  Dimensions,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { StationItem, getCoverColor } from '../../data/mockData';
import StationCover from './StationCover';

interface PublishedGridPageProps {
  stations: StationItem[];
  artists: string[];
  onBack: () => void;
  onStationPress: (station: StationItem) => void;
}

type GridTab = 'history' | 'curated' | 'artists';

const TABS: { key: GridTab; label: string }[] = [
  { key: 'history', label: '历史' },
  { key: 'curated', label: '精选' },
  { key: 'artists', label: '艺人' },
];

const screenWidth = Dimensions.get('window').width;
const PADDING = 20;
const GAP = 14;
const NUM_COLUMNS = 2;
const CARD_WIDTH = (screenWidth - PADDING * 2 - GAP) / NUM_COLUMNS;

const ARTIST_COLS = 3;
const ARTIST_GAP = 16;
const AVATAR_SIZE = (screenWidth - PADDING * 2 - ARTIST_GAP * (ARTIST_COLS - 1)) / ARTIST_COLS;

function formatRelativeTime(timestamp?: number): string {
  if (!timestamp) return '';
  const diff = Date.now() - timestamp;
  const days = Math.floor(diff / 86400000);
  if (days < 1) return '今天';
  if (days === 1) return '1天前';
  if (days < 7) return `${days}天前`;
  if (days < 14) return '1周前';
  if (days < 30) return `${Math.floor(days / 7)}周前`;
  return `${Math.floor(days / 30)}月前`;
}

export default function PublishedGridPage({
  stations,
  artists,
  onBack,
  onStationPress,
}: PublishedGridPageProps) {
  const [pageIndex, setPageIndex] = useState(0);
  const scrollRef = useRef<ScrollView>(null);

  const historyData = [...stations].sort(
    (a, b) => (b.createdAt ?? 0) - (a.createdAt ?? 0),
  );
  const curatedData = historyData.filter((s) => s.isFeatured);

  // Unique genres from published stations (for History header)
  const genreSet = new Set(stations.map((s) => s.genre).filter(Boolean) as string[]);
  const genres = Array.from(genreSet);

  const activeTab = TABS[pageIndex].key;

  const scrollToPage = (index: number) => {
    scrollRef.current?.scrollTo({ x: index * screenWidth, animated: true });
  };

  const onMomentumScrollEnd = (e: any) => {
    const idx = Math.round(e.nativeEvent.contentOffset.x / screenWidth);
    setPageIndex(idx);
  };

  const renderStationItem = ({ item }: { item: StationItem }) => (
    <TouchableOpacity
      style={styles.card}
      activeOpacity={0.6}
      onPress={() => onStationPress(item)}
    >
      <StationCover station={item} size="grid" />
      <Text style={styles.name} numberOfLines={1}>
        {item.name}
      </Text>
      <Text style={styles.subtitle} numberOfLines={1}>
        {formatRelativeTime(item.createdAt)}
      </Text>
    </TouchableOpacity>
  );

  const renderArtistItem = ({ item }: { item: string }) => (
    <View style={styles.artistCell}>
      <View
        style={[
          styles.artistAvatar,
          { backgroundColor: getCoverColor(item) },
        ]}
      >
        <Text style={styles.artistInitial}>
          {item.charAt(0)}
        </Text>
      </View>
      <Text style={styles.artistName} numberOfLines={1}>
        {item}
      </Text>
    </View>
  );

  return (
    <SafeAreaView style={styles.safe} edges={['top']}>
      {/* Header */}
      <View style={styles.header}>
        <TouchableOpacity
          onPress={onBack}
          activeOpacity={0.7}
          hitSlop={{ top: 8, bottom: 8, left: 8, right: 8 }}
        >
          <Ionicons
            name="chevron-back"
            size={24}
            color="rgba(255,255,255,0.7)"
          />
        </TouchableOpacity>
        <Text style={styles.headerTitle}>电台档案</Text>
        <View style={styles.headerSpacer} />
      </View>

      {/* Tabs */}
      <View style={styles.tabBar}>
        {TABS.map((tab, i) => {
          const isActive = i === pageIndex;
          return (
            <TouchableOpacity
              key={tab.key}
              onPress={() => scrollToPage(i)}
              style={styles.tabItem}
              activeOpacity={0.7}
            >
              <Text style={[styles.tabLabel, isActive && styles.tabLabelActive]}>
                {tab.label}
              </Text>
              {isActive && <View style={styles.tabIndicator} />}
            </TouchableOpacity>
          );
        })}
      </View>

      {/* Paged Content */}
      <ScrollView
        ref={scrollRef}
        horizontal
        pagingEnabled
        showsHorizontalScrollIndicator={false}
        onMomentumScrollEnd={onMomentumScrollEnd}
        style={styles.pager}
      >
        {/* Page 0 — History */}
        <View style={styles.page}>
          <FlatList
            data={historyData}
            keyExtractor={(item) => item.id}
            renderItem={renderStationItem}
            numColumns={NUM_COLUMNS}
            contentContainerStyle={styles.gridContent}
            columnWrapperStyle={styles.gridRow}
            showsVerticalScrollIndicator={false}
            ListHeaderComponent={
              genres.length > 0 ? (
                <View style={styles.genreRow}>
                  {genres.map((genre) => (
                    <View key={genre} style={styles.genreTag}>
                      <Text style={styles.genreTagText}>{genre}</Text>
                    </View>
                  ))}
                </View>
              ) : null
            }
          />
        </View>

        {/* Page 1 — Curated */}
        <View style={styles.page}>
          {curatedData.length === 0 ? (
            <View style={styles.emptyContainer}>
              <Text style={styles.emptyText}>暂无精选电台</Text>
            </View>
          ) : (
            <FlatList
              data={curatedData}
              keyExtractor={(item) => item.id}
              renderItem={renderStationItem}
              numColumns={NUM_COLUMNS}
              contentContainerStyle={styles.gridContent}
              columnWrapperStyle={styles.gridRow}
              showsVerticalScrollIndicator={false}
            />
          )}
        </View>

        {/* Page 2 — Artists */}
        <View style={styles.page}>
          <FlatList
            data={artists}
            keyExtractor={(item) => item}
            renderItem={renderArtistItem}
            numColumns={ARTIST_COLS}
            contentContainerStyle={styles.artistContent}
            columnWrapperStyle={styles.artistRow}
            showsVerticalScrollIndicator={false}
          />
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: {
    flex: 1,
    backgroundColor: '#121212',
  },

  /* ---- Header ---- */
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingTop: 16,
    paddingBottom: 12,
    paddingHorizontal: PADDING,
  },
  headerTitle: {
    flex: 1,
    textAlign: 'center',
    color: '#fff',
    fontSize: 18,
    fontWeight: '600',
  },
  headerSpacer: {
    width: 24,
  },

  /* ---- Tabs ---- */
  tabBar: {
    flexDirection: 'row',
    paddingHorizontal: PADDING,
    paddingBottom: 4,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: 'rgba(255,255,255,0.08)',
  },
  tabItem: {
    marginRight: 28,
    paddingBottom: 10,
    alignItems: 'center',
  },
  tabLabel: {
    fontSize: 14,
    color: 'rgba(255,255,255,0.4)',
    fontWeight: '500',
  },
  tabLabelActive: {
    color: '#fff',
  },
  tabIndicator: {
    position: 'absolute',
    bottom: 0,
    width: 16,
    height: 2,
    borderRadius: 1,
    backgroundColor: '#fff',
  },

  /* ---- Paged ScrollView ---- */
  pager: {
    flex: 1,
  },
  page: {
    width: screenWidth,
  },

  /* ---- Genre Tags ---- */
  genreRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
    marginBottom: 14,
  },
  genreTag: {
    backgroundColor: 'rgba(255,255,255,0.08)',
    borderRadius: 10,
    paddingHorizontal: 22,
    paddingVertical: 8,
  },
  genreTagText: {
    color: 'rgba(255,255,255,0.55)',
    fontSize: 14,
    fontWeight: '500',
  },

  /* ---- Station Grid ---- */
  gridContent: {
    paddingHorizontal: PADDING - GAP / 2,
    paddingTop: 20,
    paddingBottom: 40,
  },
  gridRow: {
    marginBottom: GAP,
  },
  card: {
    width: CARD_WIDTH,
    marginHorizontal: GAP / 2,
  },
  name: {
    color: '#fff',
    fontSize: 13,
    fontWeight: '600',
    marginTop: 10,
  },
  subtitle: {
    color: 'rgba(255,255,255,0.35)',
    fontSize: 11,
    marginTop: 4,
  },

  /* ---- Artists Grid ---- */
  artistContent: {
    paddingHorizontal: PADDING - ARTIST_GAP / 2,
    paddingTop: 24,
    paddingBottom: 40,
  },
  artistRow: {
    marginBottom: ARTIST_GAP,
  },
  artistCell: {
    width: AVATAR_SIZE,
    alignItems: 'center',
    marginHorizontal: ARTIST_GAP / 2,
  },
  artistAvatar: {
    width: AVATAR_SIZE,
    height: AVATAR_SIZE,
    borderRadius: AVATAR_SIZE / 2,
    justifyContent: 'center',
    alignItems: 'center',
  },
  artistInitial: {
    color: 'rgba(255,255,255,0.7)',
    fontSize: Math.max(AVATAR_SIZE * 0.38, 18),
    fontWeight: '700',
  },
  artistName: {
    color: 'rgba(255,255,255,0.6)',
    fontSize: 13,
    fontWeight: '500',
    marginTop: 8,
    textAlign: 'center',
  },

  /* ---- Empty State ---- */
  emptyContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: PADDING,
  },
  emptyText: {
    color: 'rgba(255,255,255,0.3)',
    fontSize: 14,
  },
});
