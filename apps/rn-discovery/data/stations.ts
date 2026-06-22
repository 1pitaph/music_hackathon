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
  '1': '#D8633C',
  '2': '#C9A23E',
  '3': '#8C7355',
  '4': '#B5562E',
  '5': '#5C4A38',
  '6': '#9C6B3E',
};

export const stations: Station[] = [
  {
    id: '1', title: '三点四十的厨房', coverImage: '',
    briefIntro: '深夜路过厨房时顺手按下的录音',
    description: '这是一个在凌晨三点四十分偶然开始的电台。那天鲸鱼睡不着，路过厨房时发现水龙头没关紧，水滴打在铁盘上的声音意外地好听。从那以后，厨房里的每一件器具——锅铲、砧板、蒸笼——都成了乐器。这里没有乐谱，只有锅碗瓢盆的即兴合奏。',
    hostName: '鲸鱼睡着了', genre: 'Lo-Fi / 氛围', favorites: 2340,
    songs: [
      { id: 's1', title: 'Kitchen Light', artist: '鲸鱼睡着了' },
      { id: 's2', title: '3:40 AM', artist: '鲸鱼睡着了' },
      { id: 's3', title: 'Breadcrumbs', artist: '鲸鱼睡着了' },
      { id: 's4', title: 'The Kettle Whistles', artist: '鲸鱼睡着了' },
      { id: 's5', title: '未完成的食谱', artist: '鲸鱼睡着了' },
    ],
  },
  {
    id: '2', title: '邻居的钢琴课', coverImage: '',
    briefIntro: '练习曲弹错的部分比弹对的部分好听',
    description: '隔壁阿姨每周二下午教钢琴。透过墙壁传过来的声音，最动人的永远是那些弹错的音符——车尔尼练习曲里突然冒出的即兴装饰音，或者巴赫赋格曲跑偏了一整个调性。这档电台收录的就是那些被老师划红叉、但阿姨觉得"还挺有意思"的片段。',
    hostName: '隔壁阿姨', genre: '古典 / 钢琴', favorites: 1890,
    songs: [
      { id: 's6', title: 'Wrong Note Right', artist: '隔壁阿姨' },
      { id: 's7', title: 'Between the Keys', artist: '隔壁阿姨' },
      { id: 's8', title: 'Practice Room Echo', artist: '隔壁阿姨' },
      { id: 's9', title: 'Metronome Dream', artist: '隔壁阿姨' },
      { id: 's10', title: '弹错的练习曲', artist: '隔壁阿姨' },
    ],
  },
  {
    id: '3', title: '末班车没追上', coverImage: '',
    briefIntro: '适合站在路灯下假装在等人',
    description: '迟到的春天是一个永远赶不上末班车的人。他在这座城市的每一个深夜公交站都站过——有的路灯很亮，有的干脆坏了。这档电台的歌单，是他从每一次追赶失败后回家的路上攒下来的。如果你也正站在某个路灯下，不管是在等车还是在等人，这些歌或许能陪你待一会儿。',
    hostName: '迟到的春天', genre: '独立民谣', favorites: 3200,
    songs: [
      { id: 's11', title: 'Last Bus Home', artist: '迟到的春天' },
      { id: 's12', title: 'Streetlamp Glow', artist: '迟到的春天' },
      { id: 's13', title: 'Waiting Song', artist: '迟到的春天' },
      { id: 's14', title: 'Empty Platform', artist: '迟到的春天' },
      { id: 's15', title: '末班车', artist: '迟到的春天' },
    ],
  },
  {
    id: '4', title: '褪色海报店', coverImage: '',
    briefIntro: '老海报店收音机常年没人换台',
    description: 'rec.在海报店兼职看店的第二年，收音机还是那台收音机，频道还是那个频道。墙上贴满了上世纪电影海报，阳光照进来的时候，有些海报的颜色已经褪到几乎认不出原来的片名。这档电台放的音乐，跟这家店的收音机一个脾气——老的、慢的、不想被换台的。',
    hostName: 'rec.', genre: '低保真 / 独立', favorites: 1560,
    songs: [
      { id: 's16', title: 'Faded Poster', artist: 'rec.' },
      { id: 's17', title: 'Radio Signal', artist: 'rec.' },
      { id: 's18', title: 'Dust on the Dial', artist: 'rec.' },
      { id: 's19', title: 'Nobody Changed the Station', artist: 'rec.' },
      { id: 's20', title: '旧海报', artist: 'rec.' },
    ],
  },
  {
    id: '5', title: '塑料花期', coverImage: '',
    briefIntro: '假花不会枯，但也不会真的开',
    description: '潦草花了两年时间做了一朵永远不会凋谢的塑料花，然后发现自己不知道该把它插在哪儿。这档电台就是那朵花——不着急证明自己是真花，也不着急让任何人喜欢它。它只是安静地开着。歌单以梦幻流行为底色，偶尔走神到低保真和独立电子。',
    hostName: '潦草', genre: '梦幻流行', favorites: 2780,
    songs: [
      { id: 's21', title: 'Fake Bloom', artist: '潦草' },
      { id: 's22', title: 'Plastic Petals', artist: '潦草' },
      { id: 's23', title: 'Never Wilts', artist: '潦草' },
      { id: 's24', title: 'Artificial Spring', artist: '潦草' },
      { id: 's25', title: '不开的花', artist: '潦草' },
    ],
  },
  {
    id: '6', title: '信号不良', coverImage: '',
    briefIntro: '收不清楚反而更适合循环播放',
    description: '三号宇航员在太空站上的主要工作是维修通讯设备。但他说最好的声音往往来自信号刚刚开始断断续续的临界点——信息变得模糊但还没完全消失，你开始认真听每一个音节。这档电台就是那个频率：不太清楚，但你也不打算调对。',
    hostName: '三号宇航员', genre: '电子 / 实验', favorites: 2100,
    songs: [
      { id: 's26', title: 'Static Noise', artist: '三号宇航员' },
      { id: 's27', title: 'Lost Transmission', artist: '三号宇航员' },
      { id: 's28', title: 'Faint Signal', artist: '三号宇航员' },
      { id: 's29', title: 'Interference', artist: '三号宇航员' },
      { id: 's30', title: '收不清楚', artist: '三号宇航员' },
    ],
  },
];
