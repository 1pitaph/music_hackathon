import { stations } from '@/data/stations';

/** 卡片区 — 随机电台推荐（10 个中随机选 4 个） */
export function getRandomCardStations() {
  const shuffled = [...stations].sort(() => Math.random() - 0.5);
  return shuffled.slice(0, 4);
}

/** 热门电台 — 按收藏量降序 */
export const popularStationIds = ['4', '1', '5', '2', '3', '9', '6', '10', '7', '8'];
