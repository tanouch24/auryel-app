/// Sonneries locales du Réveil Auryel.
///
/// Les mêmes identifiants sont utilisés par Flutter (aperçu) et Android natif
/// (sonnerie de secours). Les fichiers sont volontairement embarqués : le
/// déclenchement ne dépend donc ni de R2 ni du backend.
class WakeSoundOption {
  const WakeSoundOption({
    required this.id,
    required this.label,
    required this.assetPath,
    required this.nativeResource,
  });

  final String id;
  final String label;
  final String assetPath;
  final String nativeResource;
}

const wakeSoundOptions = <WakeSoundOption>[
  WakeSoundOption(
    id: 'freesound_community-wake-up-33353',
    label: 'Réveil doux',
    assetPath: 'assets/wake_sounds/freesound_community-wake-up-33353.mp3',
    nativeResource: 'wake_freesound_community_wake_up_33353',
  ),
  WakeSoundOption(
    id: 'freesound_community-wind-up-clock-alarm-bell-64219',
    label: 'Cloche douce',
    assetPath: 'assets/wake_sounds/freesound_community-wind-up-clock-alarm-bell-64219.mp3',
    nativeResource: 'wake_freesound_community_wind_up_clock_alarm_bell_64219',
  ),
  WakeSoundOption(
    id: 'fronbondi-skegs-sfx-loud-beeping-bedside-alarm-clock-sound-effect-mono-453117',
    label: 'Bip progressif',
    assetPath: 'assets/wake_sounds/fronbondi_skegs-sfx-loud-beeping-bedside-alarm-clock-sound-effect-mono-453117.mp3',
    nativeResource: 'wake_fronbondi_skegs_sfx_loud_beeping_bedside_alarm_clock_sound_effect_mono_453117',
  ),
  WakeSoundOption(
    id: 'lesiakower-dreamscape-alarm-clock-117680',
    label: 'Dreamscape',
    assetPath:
        'assets/wake_sounds/lesiakower-dreamscape-alarm-clock-117680.mp3',
    nativeResource: 'wake_lesiakower_dreamscape_alarm_clock_117680',
  ),
  WakeSoundOption(
    id: 'lesiakower-oversimplified-alarm-clock-113180',
    label: 'Oversimplified',
    assetPath:
        'assets/wake_sounds/lesiakower-oversimplified-alarm-clock-113180.mp3',
    nativeResource: 'wake_lesiakower_oversimplified_alarm_clock_113180',
  ),
  WakeSoundOption(
    id: 'lesiakower-synapse-alarm-clock-494967',
    label: 'Synapse',
    assetPath: 'assets/wake_sounds/lesiakower-synapse-alarm-clock-494967.mp3',
    nativeResource: 'wake_lesiakower_synapse_alarm_clock_494967',
  ),
  WakeSoundOption(
    id: 'magiaz-audio-alarm-clock-466285',
    label: 'Alarme claire',
    assetPath: 'assets/wake_sounds/magiaz-audio_alarm_clock-466285.mp3',
    nativeResource: 'wake_magiaz_audio_alarm_clock_466285',
  ),
  WakeSoundOption(
    id: 'menlova-zil-sesi-433221',
    label: 'Zil sesi',
    assetPath: 'assets/wake_sounds/menlova-zil-sesi-433221.mp3',
    nativeResource: 'wake_menlova_zil_sesi_433221',
  ),
  WakeSoundOption(
    id: 'miraclei-11l-alarm-clock-ringing-1749174723491-355771',
    label: 'Sonnerie classique',
    assetPath: 'assets/wake_sounds/miraclei-11l-alarm_clock_ringing-1749174723491-355771.mp3',
    nativeResource:
        'wake_miraclei_11l_alarm_clock_ringing_1749174723491_355771',
  ),
];

WakeSoundOption wakeSoundById(String id) => wakeSoundOptions.firstWhere(
  (sound) => sound.id == id,
  orElse: () => wakeSoundOptions.first,
);
