import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { StationItem } from '../../data/mockData';
import StationCover from './StationCover';

interface StationDetailPageProps {
  station: StationItem;
  onBack: () => void;
}

export default function StationDetailPage({
  station,
  onBack,
}: StationDetailPageProps) {
  return (
    <SafeAreaView style={styles.safe}>
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
        <Text style={styles.headerTitle} numberOfLines={1}>
          {station.name}
        </Text>
        <View style={styles.headerSpacer} />
      </View>

      {/* Content */}
      <View style={styles.content}>
        <StationCover station={station} size="detail" />
        <Text style={styles.stationName}>{station.name}</Text>
        <Text style={styles.hint}>播放功能开发中</Text>

        <TouchableOpacity
          style={styles.playButton}
          activeOpacity={0.6}
          disabled
        >
          <Ionicons name="play" size={20} color="rgba(255,255,255,0.3)" />
          <Text style={styles.playButtonText}>播放</Text>
        </TouchableOpacity>
      </View>
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
    paddingHorizontal: 20,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: 'rgba(255,255,255,0.06)',
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

  /* ---- Content ---- */
  content: {
    flex: 1,
    alignItems: 'center',
    paddingTop: 40,
    paddingHorizontal: 20,
  },
  stationName: {
    color: '#fff',
    fontSize: 22,
    fontWeight: '700',
    marginTop: 24,
    textAlign: 'center',
  },
  hint: {
    color: 'rgba(255,255,255,0.4)',
    fontSize: 14,
    marginTop: 12,
  },
  playButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 40,
    backgroundColor: 'rgba(255,255,255,0.08)',
    borderRadius: 8,
    paddingVertical: 14,
    paddingHorizontal: 40,
    gap: 8,
  },
  playButtonText: {
    color: 'rgba(255,255,255,0.3)',
    fontSize: 16,
    fontWeight: '600',
  },
});
