export interface StationItem {
  id: string;
  name: string;
  coverUrl: string | null;
  coverImage?: any; // require('../../assets/covers/...') 本地封面图
  createdAt?: number;
  isFeatured?: boolean;
  genre?: string;
}

export interface UserProfile {
  nickname: string;
  avatarUrl: string | null;
  avatarImage?: any; // require('../../assets/avatar.jpg') 用户头像
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
  avatarImage: require('../../assets/avatar.jpg'),
  avatarColor: '#2a2a2a',
  bio: 'Your sound. Your story.',
  stats: {
    listeningHours: 342,
    stationsCount: 28,
    likesCount: 1247,
  },
  nowPlaying: { id: 'p1', name: 'Midnight Blue Note', coverUrl: null, coverImage: require('../../assets/covers/Midnight Blue Note.jpg') },
  published: [
    { id: 'p1', name: 'Midnight Blue Note', coverUrl: null, coverImage: require('../../assets/covers/Midnight Blue Note.jpg'), createdAt: Date.now() - 2 * 86400000, isFeatured: true, genre: 'Jazz' },
    { id: 'p2', name: '霓虹雨', coverUrl: null, coverImage: require('../../assets/covers/霓虹雨.jpg'), createdAt: Date.now() - 5 * 86400000, genre: 'Electronic' },
    { id: 'p3', name: 'Expired Film Darkroom', coverUrl: null, coverImage: require('../../assets/covers/Expired Film Darkroom.jpg'), createdAt: Date.now() - 8 * 86400000, isFeatured: true, genre: 'Lo-fi' },
    { id: 'p4', name: '月球背面', coverUrl: null, coverImage: require('../../assets/covers/月球背面.jpg'), createdAt: Date.now() - 12 * 86400000, isFeatured: true, genre: 'Rock' },
    { id: 'p5', name: 'Soul Shelter', coverUrl: null, coverImage: require('../../assets/covers/Soul Shelter.jpg'), createdAt: Date.now() - 20 * 86400000, genre: 'Indie' },
    { id: 'p6', name: '季风航段', coverUrl: null, coverImage: require('../../assets/covers/季风航段.jpg'), createdAt: Date.now() - 25 * 86400000, isFeatured: true, genre: 'Jazz' },
    { id: 'p7', name: '凌晨三点诗歌集', coverUrl: null, coverImage: require('../../assets/covers/凌晨三点诗歌集.jpg'), createdAt: Date.now() - 30 * 86400000, genre: 'Lo-fi' },
    { id: 'p8', name: '空白磁带', coverUrl: null, coverImage: require('../../assets/covers/空白磁带.jpg'), createdAt: Date.now() - 35 * 86400000, genre: 'Indie' },
    { id: 'p9', name: '九号公路 Route 9', coverUrl: null, coverImage: require('../../assets/covers/九号公路 Route 9.jpg'), createdAt: Date.now() - 40 * 86400000, genre: 'Rock' },
    { id: 'p10', name: '喫茶店巡礼', coverUrl: null, coverImage: require('../../assets/covers/喫茶店巡礼.jpg'), createdAt: Date.now() - 45 * 86400000, isFeatured: true, genre: 'Jazz' },
  ],
  saved: [
    { id: 's1', name: '季风航段', coverUrl: null, coverImage: require('../../assets/covers/季风航段.jpg') },
    { id: 's2', name: '凌晨三点诗歌集', coverUrl: null, coverImage: require('../../assets/covers/凌晨三点诗歌集.jpg') },
    { id: 's3', name: '空白磁带', coverUrl: null, coverImage: require('../../assets/covers/空白磁带.jpg') },
    { id: 's4', name: '九号公路 Route 9', coverUrl: null, coverImage: require('../../assets/covers/九号公路 Route 9.jpg') },
    { id: 's5', name: '喫茶店巡礼', coverUrl: null, coverImage: require('../../assets/covers/喫茶店巡礼.jpg') },
    { id: 's6', name: 'Midnight Blue Note', coverUrl: null, coverImage: require('../../assets/covers/Midnight Blue Note.jpg') },
  ],
  recentlyPlayed: [
    { id: 'r1', name: 'Midnight Blue Note', coverUrl: null, coverImage: require('../../assets/covers/Midnight Blue Note.jpg') },
    { id: 'r2', name: '季风航段', coverUrl: null, coverImage: require('../../assets/covers/季风航段.jpg') },
    { id: 'r3', name: '霓虹雨', coverUrl: null, coverImage: require('../../assets/covers/霓虹雨.jpg') },
    { id: 'r4', name: '凌晨三点诗歌集', coverUrl: null, coverImage: require('../../assets/covers/凌晨三点诗歌集.jpg') },
    { id: 'r5', name: 'Soul Shelter', coverUrl: null, coverImage: require('../../assets/covers/Soul Shelter.jpg') },
    { id: 'r6', name: '空白磁带', coverUrl: null, coverImage: require('../../assets/covers/空白磁带.jpg') },
    { id: 'r7', name: 'Expired Film Darkroom', coverUrl: null, coverImage: require('../../assets/covers/Expired Film Darkroom.jpg') },
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
