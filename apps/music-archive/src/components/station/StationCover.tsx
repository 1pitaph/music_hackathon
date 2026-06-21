import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { StationItem, getCoverColor } from '../../data/mockData';

interface StationCoverProps {
  station: StationItem;
  size?: 'list' | 'detail';
}

export default function StationCover({ station, size = 'list' }: StationCoverProps) {
  const dim = size === 'detail' ? 120 : 56;
  const radius = size === 'detail' ? 12 : 6;
  const fontSize = size === 'detail' ? 48 : 22;

  return (
    <View
      style={[
        styles.cover,
        {
          width: dim,
          height: dim,
          borderRadius: radius,
          backgroundColor: getCoverColor(station.id),
        },
      ]}
    >
      <Text style={[styles.letter, { fontSize }]}>
        {station.name.charAt(0)}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  cover: {
    justifyContent: 'center',
    alignItems: 'center',
  },
  letter: {
    color: 'rgba(255,255,255,0.7)',
    fontWeight: '700',
  },
});
