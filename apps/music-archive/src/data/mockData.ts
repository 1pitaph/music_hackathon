export interface StationItem {
  id: string;
  name: string;
  coverUrl: string | null;
  createdAt?: number;
  isFeatured?: boolean;
  genre?: string;
}

export interface UserProfile {
  nickname: string;
  avatarUrl: string | null;
  avatarColor: string;
  bio: string;
  stats: {
    listeningHours: number;
    stationsCount: number;
    likesCount: number;
  };
  nowPlaying: StationItem | null;
  published: StationItem[];
  saved: StationItem[];
  recentlyPlayed: StationItem[];
  artists: string[];
}

// ====== Cover Color Mapping ======

export const COVER_COLORS = [
  '#8B5E3C',
  '#C75B39',
  '#3A6B5C',
  '#5B4A7A',
  '#D4956A',
];

export function getCoverColor(stationId: string): string {
  let hash = 0;
  for (let i = 0; i < stationId.length; i++) {
    hash = ((hash << 5) - hash + stationId.charCodeAt(i)) | 0;
  }
  return COVER_COLORS[Math.abs(hash) % COVER_COLORS.length];
}

export const mockUserProfile: UserProfile = {
  nickname: 'Mine Radio',
  avatarUrl: null,
  avatarColor: '#2a2a2a',
  bio: 'Your sound. Your story.',
  stats: {
    listeningHours: 342,
    stationsCount: 28,
    likesCount: 1247,
  },
  nowPlaying: { id: 'p1', name: 'Late Night Lo-fi', coverUrl: null },
  published: [
    { id: 'p1', name: 'Late Night Lo-fi', coverUrl: null, createdAt: Date.now() - 2 * 86400000, isFeatured: true, genre: 'Lo-fi' },
    { id: 'p2', name: 'Morning Coffee', coverUrl: null, createdAt: Date.now() - 5 * 86400000, genre: 'Jazz' },
    { id: 'p3', name: 'Weekend Vinyl', coverUrl: null, createdAt: Date.now() - 8 * 86400000, isFeatured: true, genre: 'Rock' },
    { id: 'p4', name: 'Indie Discovery', coverUrl: null, createdAt: Date.now() - 12 * 86400000, isFeatured: true, genre: 'Indie' },
    { id: 'p5', name: 'Electronic Hour', coverUrl: null, createdAt: Date.now() - 20 * 86400000, genre: 'Electronic' },
  ],
  saved: [
    { id: 's1', name: 'Jazz Standard', coverUrl: null },
    { id: 's2', name: 'Classic Rock Radio', coverUrl: null },
    { id: 's3', name: 'Ambient Waves', coverUrl: null },
    { id: 's4', name: 'Hip Hop Daily', coverUrl: null },
    { id: 's5', name: 'Acoustic Sessions', coverUrl: null },
    { id: 's6', name: 'Soul Kitchen', coverUrl: null },
  ],
  recentlyPlayed: [
    { id: 'r1', name: 'Late Night Lo-fi', coverUrl: null },
    { id: 'r2', name: 'Jazz Standard', coverUrl: null },
    { id: 'r3', name: 'Morning Coffee', coverUrl: null },
    { id: 'r4', name: 'Ambient Waves', coverUrl: null },
    { id: 'r5', name: 'Electronic Hour', coverUrl: null },
    { id: 'r6', name: 'Classic Rock Radio', coverUrl: null },
    { id: 'r7', name: 'Weekend Vinyl', coverUrl: null },
  ],
  artists: [
    'Billie Eilish',
    'Laufey',
    'Frank Ocean',
    'Daniel Caesar',
    'Joji',
    'Keshi',
  ],
};
