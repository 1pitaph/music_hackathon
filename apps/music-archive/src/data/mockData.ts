export interface StationItem {
  id: string;
  name: string;
  coverUrl: string | null;
}

export interface UserProfile {
  nickname: string;
  avatarUrl: string | null;
  stats: {
    listeningHours: number;
    stationsCount: number;
    likesCount: number;
  };
  nowPlaying: StationItem | null;
  published: StationItem[];
  saved: StationItem[];
  recentlyPlayed: StationItem[];
}

export const mockUserProfile: UserProfile = {
  nickname: 'pp',
  avatarUrl: null,
  stats: {
    listeningHours: 342,
    stationsCount: 28,
    likesCount: 1247,
  },
  nowPlaying: null,
  published: [
    { id: 'p1', name: 'Late Night Lo-fi', coverUrl: null },
    { id: 'p2', name: 'Morning Coffee', coverUrl: null },
    { id: 'p3', name: 'Weekend Vinyl', coverUrl: null },
    { id: 'p4', name: 'Indie Discovery', coverUrl: null },
    { id: 'p5', name: 'Electronic Hour', coverUrl: null },
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
};
