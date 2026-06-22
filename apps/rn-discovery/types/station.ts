export interface Song {
  id: string;
  title: string;
  artist: string;
}

export interface Station {
  id: string;
  title: string;
  coverImage: string;
  /** 一句话简介 — 卡片非展开态紧贴创作者名下方显示，最多一行 */
  briefIntro: string;
  /** 电台详细介绍 — 卡片展开后"关于此电台"下方显示 */
  description: string;
  hostName: string;
  genre: string;
  favorites: number;
  songs: Song[];
}
