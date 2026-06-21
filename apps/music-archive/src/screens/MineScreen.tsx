import React, { useState } from 'react';
import {
  View,
  Text,
  ScrollView,
  StyleSheet,
  TouchableOpacity,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { UserProfile, StationItem } from '../data/mockData';
import StationCover from '../components/station/StationCover';
import StationDetailPage from '../components/station/StationDetailPage';
import PublishedGridPage from '../components/station/PublishedGridPage';

type MinePage = 'list' | 'stationDetail' | 'publishedGrid';

interface MineScreenProps {
  profile: UserProfile;
  onNavigateToSettings: () => void;
}

// ====== Helpers ======

function formatRelativeTime(timestamp?: number): string {
  if (!timestamp) return '';
  const diff = Date.now() - timestamp;
  const days = Math.floor(diff / 86400000);
  if (days < 1) return 'Today';
  if (days === 1) return '1 day ago';
  if (days < 7) return `${days} days ago`;
  if (days < 14) return '1 week ago';
  if (days < 30) return `${Math.floor(days / 7)} weeks ago`;
  return `${Math.floor(days / 30)} months ago`;
}

const PANELS = [
  { key: 'recentlyPlayed', label: 'Recently Played' },
  { key: 'saved', label: 'Saved' },
] as const;

type PanelKey = (typeof PANELS)[number]['key'];

// ====== Main Screen ======

export default function MineScreen({
  profile,
  onNavigateToSettings,
}: MineScreenProps) {
  const [page, setPage] = useState<MinePage>('list');
  const [selectedStation, setSelectedStation] = useState<StationItem | null>(
    null,
  );
  const [expanded, setExpanded] = useState<Record<PanelKey, boolean>>({
    recentlyPlayed: true,
    saved: true,
  });

  const togglePanel = (key: PanelKey) => {
    setExpanded((prev) => ({ ...prev, [key]: !prev[key] }));
  };

  // Recently published — sorted by createdAt desc, top 5
  const recentStations = [...profile.published]
    .sort((a, b) => (b.createdAt ?? 0) - (a.createdAt ?? 0))
    .slice(0, 5);

  // Station detail page
  if (page === 'stationDetail' && selectedStation) {
    return (
      <StationDetailPage
        station={selectedStation}
        onBack={() => setPage('list')}
      />
    );
  }

  // Published grid page
  if (page === 'publishedGrid') {
    return (
      <PublishedGridPage
        stations={profile.published}
        artists={profile.artists}
        onBack={() => setPage('list')}
        onStationPress={(station) => {
          setSelectedStation(station);
          setPage('stationDetail');
        }}
      />
    );
  }

  return (
    <SafeAreaView style={styles.safe} edges={['top']}>
      {/* ====== Fixed Compact Header ====== */}
      <View style={styles.fixedHeader}>
        {/* Settings */}
        <View style={styles.topRow}>
          <View style={styles.topRowSpacer} />
          <TouchableOpacity
            onPress={onNavigateToSettings}
            activeOpacity={0.7}
            hitSlop={{ top: 8, bottom: 8, left: 8, right: 8 }}
          >
            <Ionicons
              name="settings-outline"
              size={22}
              color="rgba(255,255,255,0.7)"
            />
          </TouchableOpacity>
        </View>

        {/* Identity Card */}
        <View style={styles.identityCard}>
          <View style={[styles.avatar, { backgroundColor: profile.avatarColor }]}>
            <Text style={styles.avatarText}>
              {profile.nickname.charAt(0)}
            </Text>
          </View>
          <Text style={styles.title}>{profile.nickname}</Text>
          <Text style={styles.bio}>{profile.bio}</Text>
        </View>

        {/* Stats */}
        <View style={styles.statsRow}>
          <View style={styles.statItem}>
            <Text style={styles.statNumber}>
              {profile.stats.listeningHours}
            </Text>
            <Text style={styles.statLabel}>Hours</Text>
          </View>
          <View style={styles.statItem}>
            <Text style={styles.statNumber}>
              {profile.stats.stationsCount}
            </Text>
            <Text style={styles.statLabel}>Stations</Text>
          </View>
          <View style={styles.statItem}>
            <Text style={styles.statNumber}>
              {profile.stats.likesCount.toLocaleString()}
            </Text>
            <Text style={styles.statLabel}>Likes</Text>
          </View>
        </View>
      </View>

      {/* ====== Scrollable Content ====== */}
      <ScrollView
        style={styles.bodyScroll}
        contentContainerStyle={styles.bodyScrollContent}
        showsVerticalScrollIndicator={false}
      >
        {/* Recently Published */}
        <View style={styles.sectionHeader}>
          <View style={styles.sectionHeaderLeft}>
            <Ionicons name="radio" size={18} color="rgba(255,255,255,0.6)" />
            <Text style={styles.sectionTitle}>Radio Archive</Text>
          </View>
          <TouchableOpacity
            onPress={() => setPage('publishedGrid')}
            activeOpacity={0.6}
          >
            <Text style={styles.seeAll}>See All</Text>
          </TouchableOpacity>
        </View>

        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.recentScrollContent}
        >
          {recentStations.map((station) => (
            <TouchableOpacity
              key={station.id}
              style={styles.recentCard}
              activeOpacity={0.6}
              onPress={() => {
                setSelectedStation(station);
                setPage('stationDetail');
              }}
            >
              <StationCover station={station} size="recent" />
              <Text style={styles.recentName} numberOfLines={1}>
                {station.name}
              </Text>
              <Text style={styles.recentSubtitle} numberOfLines={1}>
                {formatRelativeTime(station.createdAt)}
              </Text>
            </TouchableOpacity>
          ))}
        </ScrollView>

        {/* Expandable Panels: Recently Played / Saved */}
        {PANELS.map((panel) => {
          const isOpen = expanded[panel.key];
          const items: StationItem[] = profile[panel.key];
          return (
            <View key={panel.key} style={styles.panel}>
              <TouchableOpacity
                style={styles.panelHeader}
                activeOpacity={0.6}
                onPress={() => togglePanel(panel.key)}
              >
                <Text style={styles.panelTitle}>{panel.label}</Text>
                <Ionicons
                  name={isOpen ? 'chevron-down' : 'chevron-forward'}
                  size={18}
                  color="rgba(255,255,255,0.45)"
                />
              </TouchableOpacity>

              {isOpen && (
                <View style={styles.panelBody}>
                  {items.length === 0 ? (
                    <Text style={styles.emptyText}>Nothing here yet.</Text>
                  ) : (
                    items.map((station, index) => (
                      <View key={station.id}>
                        {index > 0 && <View style={styles.listDivider} />}
                        <TouchableOpacity
                          style={styles.listItem}
                          activeOpacity={0.6}
                          onPress={() => {
                            setSelectedStation(station);
                            setPage('stationDetail');
                          }}
                        >
                          <StationCover station={station} />
                          <Text style={styles.stationName}>
                            {station.name}
                          </Text>
                        </TouchableOpacity>
                      </View>
                    ))
                  )}
                </View>
              )}
            </View>
          );
        })}

        <View style={styles.listBottom} />
      </ScrollView>
    </SafeAreaView>
  );
}

// ====== Styles ======

const styles = StyleSheet.create({
  safe: {
    flex: 1,
    backgroundColor: '#121212',
  },

  /* ---- Fixed Header ---- */
  fixedHeader: {
    paddingHorizontal: 20,
    paddingBottom: 12,
  },

  /* ---- Top Row: Settings ---- */
  topRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    paddingTop: 8,
  },
  topRowSpacer: {
    flex: 1,
  },

  /* ---- Identity Card ---- */
  identityCard: {
    alignItems: 'center',
    marginTop: 8,
  },
  avatar: {
    width: 80,
    height: 80,
    borderRadius: 40,
    borderWidth: 2,
    borderColor: 'rgba(255,255,255,0.15)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  avatarText: {
    color: 'rgba(255,255,255,0.7)',
    fontSize: 28,
    fontWeight: '600',
  },
  title: {
    color: '#fff',
    fontSize: 28,
    fontWeight: '700',
    marginTop: 16,
  },
  bio: {
    fontSize: 13,
    fontWeight: '400',
    color: 'rgba(255,255,255,0.4)',
    marginTop: 8,
    textAlign: 'center',
  },

  /* ---- Stats ---- */
  statsRow: {
    flexDirection: 'row',
    marginTop: 20,
  },
  statItem: {
    flex: 1,
    alignItems: 'center',
  },
  statNumber: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
  statLabel: {
    color: 'rgba(255,255,255,0.35)',
    fontSize: 10,
    fontWeight: '500',
    letterSpacing: 0.5,
    marginTop: 4,
  },

  /* ---- Recently Published ---- */
  sectionHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginTop: 16,
    marginBottom: 14,
  },
  sectionHeaderLeft: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  sectionTitle: {
    color: '#fff',
    fontSize: 15,
    fontWeight: '700',
    marginLeft: 8,
  },
  seeAll: {
    color: 'rgba(255,255,255,0.4)',
    fontSize: 13,
    fontWeight: '500',
  },
  recentScrollContent: {
    paddingRight: 20,
    gap: 14,
  },
  recentCard: {
    width: 104,
  },
  recentName: {
    color: '#fff',
    fontSize: 13,
    fontWeight: '600',
    marginTop: 10,
  },
  recentSubtitle: {
    color: 'rgba(255,255,255,0.35)',
    fontSize: 11,
    marginTop: 4,
  },

  /* ---- Body Scroll ---- */
  bodyScroll: {
    flex: 1,
  },
  bodyScrollContent: {
    paddingHorizontal: 20,
  },

  /* ---- Expandable Panels ---- */
  panel: {
    marginTop: 4,
  },
  panelHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: 16,
  },
  panelTitle: {
    color: '#fff',
    fontSize: 15,
    fontWeight: '700',
  },
  panelBody: {
    paddingBottom: 8,
  },
  listItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 14,
  },
  listDivider: {
    height: StyleSheet.hairlineWidth,
    backgroundColor: 'rgba(255,255,255,0.06)',
  },
  stationName: {
    color: '#fff',
    fontSize: 15,
    fontWeight: '500',
    marginLeft: 14,
  },

  /* ---- Empty ---- */
  emptyText: {
    color: 'rgba(255,255,255,0.3)',
    fontSize: 14,
    paddingTop: 16,
  },

  /* ---- List Bottom ---- */
  listBottom: {
    height: 24,
  },
});
