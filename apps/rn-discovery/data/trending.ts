import { stations } from '@/data/stations';

/**
 * 卡片区 — 随机电台推荐（与热门列表独立）。
 * 每次进入页面从中随机选 4 个。
 */
export function getRandomCardStations() {
  const shuffled = [...stations].sort(() => Math.random() - 0.5);
  return shuffled.slice(0, 4);
}

/**
 * 热门电台 — 按 popularity 降序的固定列表。
 * 点击进入详情页，不影响上方卡片区。
 */
export const popularStationIds = ['3', '1', '6', '2', '5', '4'];
