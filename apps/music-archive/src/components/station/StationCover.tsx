import React, { useState } from 'react';
import { View, Text, Image, StyleSheet } from 'react-native';
import { StationItem, getCoverColor } from '../../data/mockData';

interface StationCoverProps {
  station: StationItem;
  size?: 'mini' | 'list' | 'recent' | 'grid' | 'detail';
}

export default function StationCover({ station, size = 'list' }: StationCoverProps) {
  const [imageFailed, setImageFailed] = useState(false);

  const dim =
    size === 'detail' ? 120 :
    size === 'grid' ? 150 :
    size === 'recent' ? 104 :
    size === 'mini' ? 48 : 56;
  const radius =
    size === 'detail' ? 12 :
    size === 'grid' ? 8 :
    size === 'recent' ? 8 :
    size === 'mini' ? 4 : 6;
  const fontSize =
    size === 'detail' ? 48 :
    size === 'grid' ? 56 :
    size === 'recent' ? 40 :
    size === 'mini' ? 18 : 22;

  const hasCover = station.coverImage && !imageFailed;
  const bgColor = getCoverColor(station.id);

  return (
    <View
      style={[
        styles.cover,
        {
          width: dim,
          height: dim,
          borderRadius: radius,
          backgroundColor: hasCover ? 'transparent' : bgColor,
        },
      ]}
    >
      {hasCover ? (
        <Image
          source={station.coverImage}
          style={[
            styles.image,
            {
              width: dim,
              height: dim,
              borderRadius: radius,
            },
          ]}
          onError={() => setImageFailed(true)}
          resizeMode="cover"
        />
      ) : (
        <Text style={[styles.letter, { fontSize }]}>
          {station.name.charAt(0)}
        </Text>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  cover: {
    justifyContent: 'center',
    alignItems: 'center',
    overflow: 'hidden',
  },
  image: {
    position: 'absolute',
  },
  letter: {
    color: 'rgba(255,255,255,0.7)',
    fontWeight: '700',
  },
});
