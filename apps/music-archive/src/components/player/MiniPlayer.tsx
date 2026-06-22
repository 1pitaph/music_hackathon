import React, { useState } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { StationItem } from '../../data/mockData';
import StationCover from '../station/StationCover';

interface MiniPlayerProps {
  station: StationItem | null;
  artist?: string;
}

export default function MiniPlayer({ station, artist = '未知艺人' }: MiniPlayerProps) {
  const [isPlaying, setIsPlaying] = useState(false);

  const handlePlayPause = () => {
    setIsPlaying((prev) => !prev);
  };

  const handlePress = () => {
    console.log('navigate to player detail', station?.id);
  };

  // Always show the mini player
  const displayStation = station ?? {
    id: 'default',
    name: '未在播放',
    coverUrl: null,
  };

  return (
    <TouchableOpacity
      style={styles.container}
      activeOpacity={0.8}
      onPress={handlePress}
    >
      {/* Left: Cover */}
      <StationCover station={displayStation} size="mini" />

      {/* Center: Song + Artist */}
      <View style={styles.info}>
        <Text style={styles.songName} numberOfLines={1}>
          {displayStation.name}
        </Text>
        <Text style={styles.artistName} numberOfLines={1}>
          {artist}
        </Text>
      </View>

      {/* Right: Play/Pause */}
      <TouchableOpacity
        style={styles.playButton}
        onPress={handlePlayPause}
        activeOpacity={0.6}
        hitSlop={{ top: 8, bottom: 8, left: 8, right: 8 }}
      >
        <Ionicons
          name={isPlaying ? 'pause' : 'play'}
          size={24}
          color="#fff"
        />
      </TouchableOpacity>
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#1E1E1E',
    marginHorizontal: 12,
    marginBottom: 8,
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderRadius: 12,
  },
  info: {
    flex: 1,
    marginLeft: 12,
    justifyContent: 'center',
  },
  songName: {
    fontSize: 14,
    fontWeight: '700',
    color: '#fff',
  },
  artistName: {
    fontSize: 12,
    color: '#8a8a8f',
    marginTop: 2,
  },
  playButton: {
    justifyContent: 'center',
    alignItems: 'center',
  },
});
