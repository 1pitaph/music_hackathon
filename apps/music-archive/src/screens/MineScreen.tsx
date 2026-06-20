import React, { useState, useMemo } from 'react';
import {
  View,
  Text,
  ScrollView,
  StyleSheet,
  TouchableOpacity,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { mockUserProfile, StationItem } from '../data/mockData';

type TabKey = 'published' | 'saved' | 'recentlyPlayed';

interface MineScreenProps {
  onNavigateToSettings: () => void;
}

const TABS: { key: TabKey; label: string }[] = [
  { key: 'published', label: 'Published' },
  { key: 'saved', label: 'Saved' },
  { key: 'recentlyPlayed', label: 'Recently Played' },
];

// ====== Waveform ======

const WAVEFORM_LINES = 35;
const WAVEFORM_MIN_H = 20;
const WAVEFORM_MAX_H = 60;

function pseudoRandom(seed: number): number {
  const x = Math.sin(seed * 12.9898 + 78.233) * 43758.5453;
  return x - Math.floor(x);
}

function Waveform() {
  const lines = useMemo(() => {
    return Array.from({ length: WAVEFORM_LINES }, (_, i) => {
      const h =
        WAVEFORM_MIN_H +
        pseudoRandom(i * 3.7 + 0.5) * (WAVEFORM_MAX_H - WAVEFORM_MIN_H);
      const centerDist =
        Math.abs(i - (WAVEFORM_LINES - 1) / 2) / ((WAVEFORM_LINES - 1) / 2);
      const opacity = 1.0 - centerDist * 0.7;
      return { height: Math.round(h), opacity: Math.round(opacity * 100) / 100 };
    });
  }, []);

  return (
    <View style={styles.waveform}>
      {lines.map((line, i) => (
        <View
          key={i}
          style={[
            styles.waveformLine,
            { height: line.height, opacity: line.opacity },
          ]}
        />
      ))}
    </View>
  );
}

// ====== Station Cover ======

function StationCover({ station }: { station: StationItem }) {
  return (
    <View style={styles.cover}>
      <Text style={styles.coverLetter}>{station.name.charAt(0)}</Text>
    </View>
  );
}

// ====== Main Screen ======

export default function MineScreen({ onNavigateToSettings }: MineScreenProps) {
  const profile = mockUserProfile;
  const [activeTab, setActiveTab] = useState<TabKey>('published');
  const stations: StationItem[] = profile[activeTab];

  return (
    <SafeAreaView style={styles.safe}>
      {/* ====== Fixed Area ====== */}
      <View style={styles.fixedArea}>
        {/* Row 1: Avatar + Settings */}
        <View style={styles.topRow}>
          <View style={styles.avatar}>
            <Text style={styles.avatarText}>
              {profile.nickname.charAt(0)}
            </Text>
          </View>
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

        {/* Identity + Waveform */}
        <View style={styles.identityArea}>
          <View style={styles.identityText}>
            <Text style={styles.title}>Mine Radio</Text>
            <View style={styles.subtitleRow}>
              <View style={styles.cyanDot} />
              <Text style={styles.subtitle} numberOfLines={1}>
                {profile.nowPlaying
                  ? `Now Playing: ${profile.nowPlaying.name}`
                  : `Now Playing: ${profile.published[0]?.name ?? ''}`}
              </Text>
            </View>
          </View>
          <View style={styles.waveformWrap}>
            <Waveform />
          </View>
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
              <View style={styles.listItem}>
                <StationCover station={station} />
                <Text style={styles.stationName}>{station.name}</Text>
              </View>
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

  /* ---- Top Row: Avatar + Settings ---- */
  topRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    paddingTop: 16,
  },
  topRowSpacer: {
    flex: 1,
  },
  avatar: {
    width: 60,
    height: 60,
    borderRadius: 30,
    backgroundColor: '#2a2a2a',
    borderWidth: 2,
    borderColor: '#fff',
    justifyContent: 'center',
    alignItems: 'center',
  },
  avatarText: {
    color: 'rgba(255,255,255,0.7)',
    fontSize: 24,
    fontWeight: '600',
  },

  /* ---- Identity Area ---- */
  identityArea: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    paddingTop: 24,
    paddingBottom: 8,
  },
  identityText: {
    flex: 1,
  },
  title: {
    color: '#fff',
    fontSize: 28,
    fontWeight: '700',
  },
  subtitleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 8,
  },
  cyanDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: '#00d4aa',
    marginRight: 8,
  },
  subtitle: {
    fontSize: 14,
    color: '#8a8a8f',
  },

  /* ---- Waveform ---- */
  waveformWrap: {
    width: 120,
    height: 60,
    justifyContent: 'flex-end',
    alignItems: 'center',
  },
  waveform: {
    flexDirection: 'row',
    alignItems: 'flex-end',
  },
  waveformLine: {
    width: 2,
    marginHorizontal: 0.75,
    backgroundColor: '#8a8a8f',
    borderRadius: 1,
  },

  /* ---- Stats ---- */
  statsRow: {
    flexDirection: 'row',
    paddingTop: 28,
  },
  statItem: {
    marginRight: 40,
  },
  statNumber: {
    color: '#fff',
    fontSize: 22,
    fontWeight: '600',
  },
  statLabel: {
    color: 'rgba(255,255,255,0.45)',
    fontSize: 13,
    marginTop: 2,
  },

  /* ---- Tab Bar ---- */
  tabBar: {
    flexDirection: 'row',
    paddingTop: 28,
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
  cover: {
    width: 56,
    height: 56,
    borderRadius: 6,
    backgroundColor: '#2a2a2a',
    justifyContent: 'center',
    alignItems: 'center',
  },
  coverLetter: {
    color: 'rgba(255,255,255,0.35)',
    fontSize: 22,
    fontWeight: '600',
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
