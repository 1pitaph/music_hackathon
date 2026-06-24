import { Station } from '@/types/station';

export const FALLBACK_STATION: Station = {
  id: 'fallback',
  title: '音乐岛',
  coverImage: '',
  briefIntro: '暂时没有可收听的电台',
  description: '',
  hostName: '音乐岛',
  genre: 'Ambient',
  favorites: 0,
  songs: [],
};

export const STATION_COLORS: Record<string, string> = {
  fallback: '#8C7355',
  '1':  '#3B5B8A',
  '2':  '#6B4B7A',
  '3':  '#8C6B4A',
  '4':  '#8A4B5B',
  '5':  '#5B7A4B',
  '6':  '#4A8A8A',
  '7':  '#7A5B3B',
  '8':  '#5B6B8A',
  '9':  '#8A5B3B',
  '10': '#4B6B5A',
};

export const stations: Station[] = [
  {
    id: '1', title: 'Midnight Blue Note', coverImage: '',
    briefIntro: '凌晨两点，蓝色音符下的都市呢喃。',
    description: '深夜睡不着的时候，翻来覆去最后还是会打开Chet Baker。这档电台没什么宏大叙事，就是一个人在沙发上瘫着，听着小号声和钢琴慢慢磨。冷爵士和苦情蓝调为主，偶尔冒出一两首灵魂乐，都是那种适合把灯光调暗、盯着天花板发呆的歌。',
    hostName: '小张在听歌', genre: '冷爵士 / 蓝调 / 灵魂', favorites: 3840,
    songs: [
      { id: 's1', title: "I'm a Fool to Want You", artist: 'Chet Baker' },
      { id: 's2', title: "Don't Know Why", artist: 'Norah Jones' },
      { id: 's3', title: "I'd Rather Go Blind", artist: 'Etta James' },
      { id: 's4', title: 'Georgia on My Mind', artist: 'Ray Charles' },
      { id: 's5', title: 'Love Is a Losing Game', artist: 'Amy Winehouse' },
    ],
  },
  {
    id: '2', title: '霓虹雨', coverImage: '',
    briefIntro: '潮湿的柏油路，模糊的车灯，和循环播放的磁带。',
    description: '这个歌单就是给下雨天准备的，特别是那种下起来没完没了、空气里全是水汽的傍晚！吉他噪音一糊上来，配上窗外的雨声，整个人就舒坦了。选曲偏迷幻和氛围，节奏慢慢晃，适合一个人对着窗户放空。',
    hostName: '404notfound', genre: '迷幻 / 氛围 / 独立摇滚', favorites: 2960,
    songs: [
      { id: 's6', title: '穿过云层', artist: '落日飞车' },
      { id: 's7', title: '山海', artist: '草东没有派对（不插电版）' },
      { id: 's8', title: 'No Surprises', artist: 'Radiohead' },
      { id: 's9', title: '乘客', artist: '王菲' },
      { id: 's10', title: 'Misread', artist: 'Kings of Convenience' },
    ],
  },
  {
    id: '3', title: 'Expired Film Darkroom', coverImage: '',
    briefIntro: '在显影液里，打捞被遗忘的旧时光。',
    description: '本人有段时间疯狂迷恋黑胶的炒豆声和磁带翻面的咔嚓声，干脆做了这个电台。选歌都是偏安静挂的——民谣、慢核、以及一点Dream Pop，全是那种人声和乐器都隔着一层雾的质感。适合周末下午整理旧物、翻相册的时候当背景音，听着听着就掉进回忆里了。',
    hostName: '暗房学徒', genre: '民谣 / 慢核 / Dream Pop', favorites: 2670,
    songs: [
      { id: 's11', title: "Tom's Diner", artist: 'Suzanne Vega' },
      { id: 's12', title: '喜欢', artist: '张悬' },
      { id: 's13', title: 'Pink Moon', artist: 'Nick Drake' },
      { id: 's14', title: 'Fade Into You', artist: 'Mazzy Star' },
      { id: 's15', title: 'Flightless Bird, American Mouth', artist: 'Iron & Wine' },
    ],
  },
  {
    id: '4', title: '月球背面', coverImage: '',
    briefIntro: '地球自转太快，我选择在背面慢半拍。',
    description: '这档电台纯粹是给自己做的——有时候就是想从人群里消失一会儿，漂浮在太空里那种感觉。所以选的歌都带着迷幻摇滚和艺术摇滚的味道，合成器嗡嗡响，吉他延迟开很大，人声若隐若现。适合深夜加班或者不想回消息的时候听，一起逃离地球吧。',
    hostName: '今天也不想说话', genre: '迷幻摇滚 / 艺术摇滚', favorites: 4120,
    songs: [
      { id: 's16', title: '十万嬉皮', artist: '万能青年旅店' },
      { id: 's17', title: 'Space Oddity', artist: 'David Bowie' },
      { id: 's18', title: 'Eventually', artist: 'Tame Impala' },
      { id: 's19', title: 'Sunday Morning', artist: 'The Velvet Underground' },
      { id: 's20', title: 'Cherry-Coloured Funk', artist: 'Cocteau Twins' },
    ],
  },
  {
    id: '5', title: 'Soul Shelter', coverImage: '',
    briefIntro: '给游荡在午夜的无处安放的灵魂，一张旧沙发。',
    description: '常年在深夜坐末班公交的人应该懂——耳机里放着老派的R&B和南方灵魂乐，看着窗外路灯一盏一盏往后倒，那种感觉真的很奇妙。这档电台选的歌都带着管乐和教堂式和声，温暖又有点粗糙，像旧唱片店里淘来的宝贝。适合凌晨写东西或者单纯睡不着的时候听。',
    hostName: '夜班巴士', genre: 'R&B / 南方灵魂 / Neo-Soul', favorites: 3580,
    songs: [
      { id: 's21', title: 'Try a Little Tenderness', artist: 'Otis Redding' },
      { id: 's22', title: "Fallin'", artist: 'Alicia Keys (Unplugged)' },
      { id: 's23', title: 'Untitled (How Does It Feel)', artist: "D'Angelo" },
      { id: 's24', title: 'River', artist: 'Leon Bridges' },
      { id: 's25', title: 'Smooth Operator', artist: 'Sade' },
    ],
  },
  {
    id: '6', title: '季风航段', coverImage: '',
    briefIntro: '关于赤道附近的风，和夏天结束时未说出口的话。',
    description: '去年夏天去了趟东南亚海边，回来之后一直怀念那种湿热的风和晃悠悠的节奏。这档电台就是那个感觉——独立流行和轻电子混搭，Groove感很强但又不吵闹，人声懒懒的，像傍晚躺在吊床上喝椰子水。适合通勤路上听，假装自己还在度假。',
    hostName: '船锚', genre: '独立流行 / 轻电子', favorites: 2310,
    songs: [
      { id: 's26', title: 'Gooey', artist: 'Glass Animals' },
      { id: 's27', title: '爱人错过', artist: '告五人' },
      { id: 's28', title: 'Warm on a Cold Night', artist: 'HONNE' },
      { id: 's29', title: 'Tadow', artist: 'Masego / FKJ' },
      { id: 's30', title: 'Open', artist: 'Rhye' },
    ],
  },
  {
    id: '7', title: '凌晨三点诗歌集', coverImage: '',
    briefIntro: '把诗唱成梦呓，把词揉进凌晨的叹息。',
    description: '也不知道为什么，一到凌晨三点就特别容易感伤，翻来覆去睡不着的时候就听这些——这档电台不追求旋律多抓耳，词比曲子更重要，每一首都是能反复咀嚼的句子。适合失眠夜，或者心里有事但说不出口的时候。',
    hostName: '诗人说梦', genre: '民谣 / 唱作人 / 诗性叙事', favorites: 1890,
    songs: [
      { id: 's31', title: 'Chelsea Hotel #2', artist: 'Leonard Cohen' },
      { id: 's32', title: "Blowin' in the Wind", artist: 'Bob Dylan' },
      { id: 's33', title: 'Selfish Gene', artist: '陈绮贞（Demo）' },
      { id: 's34', title: 'California', artist: 'Joni Mitchell' },
      { id: 's35', title: 'First Day of My Life', artist: 'Bright Eyes' },
    ],
  },
  {
    id: '8', title: '空白磁带', coverImage: '',
    briefIntro: '沉默比音乐更响亮的那个瞬间。',
    description: '有时候不是想听歌，只是需要一点声音盖住脑子里的杂音。这档电台选的全是极简的氛围音乐和慢核，钢琴、弦乐、低语般的人声，编曲都很克制，留白很多。适合看书、写东西、或者单纯躺着什么也不干。别指望有高潮，它就是一直平着，淡淡的。',
    hostName: '等雪停', genre: '氛围 / 慢核 / 极简', favorites: 1650,
    songs: [
      { id: 's36', title: 'Svefn-g-englar', artist: 'Sigur Rós' },
      { id: 's37', title: 'Holocene', artist: 'Bon Iver' },
      { id: 's38', title: '雨吁', artist: '窦唯' },
      { id: 's39', title: 'Alison', artist: 'Slowdive' },
      { id: 's40', title: 'Intro', artist: 'The xx' },
    ],
  },
  {
    id: '9', title: '九号公路 Route 9', coverImage: '',
    briefIntro: '方向盘向左，夕阳向右，音乐一路向西。',
    description: '开车的时候必须听点带劲的——经典摇滚、乡村摇滚、南方蓝调，节奏感强，吉他solo一出来就想踩油门哈哈哈。这档电台就是给我这种喜欢在公路上瞎逛的人准备的，歌单全是老炮，粗粝、野生、不修边幅。适合周末自驾或者加班回家路上把车窗摇下来吹风听。',
    hostName: 'Utopia', genre: '经典摇滚 / 乡村摇滚 / 蓝调', favorites: 2430,
    songs: [
      { id: 's41', title: 'Hotel California', artist: 'Eagles (Live acoustic)' },
      { id: 's42', title: 'American Girl', artist: 'Tom Petty' },
      { id: 's43', title: 'Proud Mary', artist: 'Creedence Clearwater Revival' },
      { id: 's44', title: 'Heart of Gold', artist: 'Neil Young' },
      { id: 's45', title: "(I Can't Get No) Satisfaction", artist: 'The Rolling Stones' },
    ],
  },
  {
    id: '10', title: '喫茶店巡礼', coverImage: '',
    briefIntro: '用一杯咖啡的时间，听完一首昭和旧情歌。',
    description: '特别喜欢日本老式喫茶店那种氛围——昏暗的灯光、厚重的木桌子、角落喇叭里放着带点沙哑的爵士或City-Pop。这档电台就是照着那个感觉做的，Bossa Nova的松弛感、昭和流行曲的复古味、以及一点坂本龙一式的古典底子。适合周末下午冲杯手冲，假装自己坐在银座地下一楼的旧咖啡馆里。',
    hostName: '铃木不在吧台', genre: 'Bossa Nova / City-Pop / 昭和', favorites: 1980,
    songs: [
      { id: 's46', title: 'Fly Me to the Moon', artist: '小野丽莎' },
      { id: 's47', title: 'Ride on Time', artist: '山下达郎' },
      { id: 's48', title: 'Merry Christmas Mr. Lawrence', artist: '坂本龙一' },
      { id: 's49', title: '黄昏のBay City', artist: '八神純子' },
      { id: 's50', title: 'Tropical Dandy', artist: '细野晴臣' },
    ],
  },
];

/** 封面图映射 — 本地 assets 路径 */
export const COVER_IMAGES: Record<string, any> = {
  '1':  require('@/assets/images/Midnight Blue Note.jpg'),
  '2':  require('@/assets/images/霓虹雨.jpg'),
  '3':  require('@/assets/images/Expired Film Darkroom.jpg'),
  '4':  require('@/assets/images/月球表面.jpg'),
  '5':  require('@/assets/images/Soul Shelter.jpg'),
  '6':  require('@/assets/images/季风航段.jpg'),
  '7':  require('@/assets/images/凌晨三点诗歌集.jpg'),
  '8':  require('@/assets/images/空白磁带.jpg'),
  '9':  require('@/assets/images/九号公路Route9.jpg'),
  '10': require('@/assets/images/喫茶店巡礼.jpg'),
};
