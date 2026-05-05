import { registerPlugin } from '@capacitor/core';

import type { RichSharePlugin } from './definitions';

/** The registered Capacitor plugin instance. */
export const RichShare = registerPlugin<RichSharePlugin>('RichShare', {
  web: () => import('./web').then((m) => new m.RichShareWeb()),
});
