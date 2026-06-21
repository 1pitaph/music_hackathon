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

type TabKey = 'published' | 'saved' | 'recentlyPlayed';
type MinePage = 'list' | 'stationDetail';

interface MineScreenProps {
  profile: UserProfile;
  onNavigateToSettings: () => void;
}

const TABS: { key: TabKey; label: string }[] = [
  { key: 'published', label: 'Published' },
  { key: 'saved', label: 'Saved' },
  { key: 'recentlyPlayed', label: 'Recently Played' },
];

// ====== Main Screen ======

export default function MineScreen({
  profile,
  onNavigateToSettings,
}: MineScreenProps) {
  const [activeTab, setActiveTab] = useState<TabKey>('published');
  const [page, setPage] = useState<MinePage>('list');
  const [selectedStation, setSelectedStation] = useState<StationItem | null>(
    null,
  );
  const stations: StationItem[] = profile[activeTab];

  // Station detail page
  if (page === 'stationDetail' && selectedStation) {
    return (
      <StationDetailPage
        station={selectedStation}
        onBack={() => setPage('list')}
      />
    );
  }

  return (
    <SafeAreaView style={styles.safe}>
      {/* ====== Fixed Header ====== */}
      <View style={styles.fixedArea}>
        {/* Row 1: Settings */}
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
          <View style={styles.subtitleRow}>
            <View style={styles.onAirDot} />
            <Text style={styles.subtitle} numberOfLines={1}>
              {profile.nowPlaying
                ? `Now Playing: ${profile.nowPlaying.name}`
                : `Now Playing: ${profile.published[0]?.name ?? ''}`}
            </Text>
          </View>
        </View>

        {/* Stats */}
        <View style={styles.statsRow}>
          <View style={styles.statCard}>
            <Text style={styles.statNumber}>
              {profile.stats.listeningHours}
            </Text>
            <Text style={styles.statLabel}>Hours</Text>
          </View>
          <View style={styles.statCard}>
            <Text style={styles.statNumber}>
              {profile.stats.stationsCount}
            </Text>
            <Text style={styles.statLabel}>Stations</Text>
          </View>
          <View style={styles.statCard}>
            <Text style={styles.statNumber}>
              {profile.stats.likesCount.toLocaleString()}
            </Text>
            <Text style={styles.statLabel}>Likes</Text>
          </View>
        </View>

        {/* Tabs */}
        <View style={styles.tabBar}>
          {TABS.map((tab) => {
            const isActive = activeTab === tab.key;
            return (
              <TouchableOpacity
                key={tab.key}
                onPress={() => setActiveTab(tab.key)}
                style={styles.tabItem}
                activeOpacity={0.7}
              >
                <Text
                  style={[styles.tabLabel, isActive && styles.tabLabelActive]}
                >
                  {tab.label}
                </Text>
                {isActive && <View style={styles.tabIndicator} />}
              </TouchableOpacity>
            );
          })}
        </View>
      </View>

      {/* ====== Scrollable List ====== */}
      <ScrollView
        style={styles.listScroll}
        contentContainerStyle={styles.listScrollContent}
        showsVerticalScrollIndicator={false}
      >
        {stations.length === 0 ? (
          <Text style={styles.emptyText}>Nothing here yet.</Text>
        ) : (
          stations.map((station, index) => (
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
                <Text style={styles.stationName}>{station.name}</Text>
              </TouchableOpacity>
            </View>
          ))
        )}
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

  /* ---- Fixed Area ---- */
  fixedArea: {
    paddingHorizontal: 20,
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
    marginTop: 12,
  },
  avatar: {
    width: 88,
    height: 88,
    borderRadius: 44,
    borderWidth: 2,
    borderColor: 'rgba(255,255,255,0.15)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  avatarText: {
    color: 'rgba(255,255,255,0.7)',
    fontSize: 32,
    fontWeight: '600',
  },
  title: {
    color: '#fff',
    fontSize: 22,
    fontWeight: '700',
    marginTop: 16,
  },
  subtitleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 8,
  },
  onAirDot: {
    width: 10,
    height: 10,
    borderRadius: 5,
    backgroundColor: '#00d4aa',
    borderWidth: 1,
    borderColor: 'rgba(0,212,170,0.3)',
    marginRight: 8,
  },
  subtitle: {
    fontSize: 13,
    fontWeight: '500',
    color: 'rgba(255,255,255,0.45)',
  },

  /* ---- Stats ---- */
  statsRow: {
    flexDirection: 'row',
    gap: 8,
    marginTop: 24,
  },
  statCard: {
    flex: 1,
    backgroundColor: '#1e1e1e',
    borderRadius: 12,
    paddingVertical: 16,
    paddingHorizontal: 12,
    alignItems: 'center',
  },
  statNumber: {
    color: '#fff',
    fontSize: 18,
    fontWeight: '600',
  },
  statLabel: {
    color: 'rgba(255,255,255,0.45)',
    fontSize: 11,
    fontWeight: '500',
    letterSpacing: 0.5,
    marginTop: 4,
  },

  /* ---- Tab Bar ---- */
  tabBar: {
    flexDirection: 'row',
    paddingTop: 20,
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

  /* ---- Scrollable List ---- */
  listScroll: {
    flex: 1,
  },
  listScrollContent: {
    paddingHorizontal: 20,
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
