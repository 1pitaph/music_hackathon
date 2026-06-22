import MaterialIcons from '@expo/vector-icons/MaterialIcons';
import { SymbolWeight, SymbolViewProps } from 'expo-symbols';
import { ComponentProps } from 'react';
import { OpaqueColorValue, type StyleProp, type TextStyle } from 'react-native';

type IconMapping = Record<SymbolViewProps['name'], ComponentProps<typeof MaterialIcons>['name']>;
type IconSymbolName = keyof typeof MAPPING;

const MAPPING = {
  'house.fill': 'home',
  'paperplane.fill': 'send',
  'chevron.left.forwardslash.chevron.right': 'code',
  'chevron.right': 'chevron-right',
  'antenna.radiowaves.left.and.right': 'radio',
  'play.fill': 'play-arrow',
  'pause.fill': 'pause',
  'heart': 'favorite-border',
  'heart.fill': 'favorite',
  'square.and.arrow.up': 'share',
  'chevron.down': 'expand-more',
  'chevron.up': 'expand-less',
  'music.note.list': 'queue-music',
  'person.crop.circle': 'account-circle',
  'backward.fill': 'skip-previous',
  'forward.fill': 'skip-next',
  'ellipsis': 'more-horiz',
  'magnifyingglass': 'search',
  'bell': 'notifications-none',
} as IconMapping;

export function IconSymbol({ name, size = 24, color, style }: {
  name: IconSymbolName; size?: number; color: string | OpaqueColorValue; style?: StyleProp<TextStyle>; weight?: SymbolWeight;
}) {
  return <MaterialIcons color={color} size={size} name={MAPPING[name]} style={style} />;
}
