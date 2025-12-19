import media from '@ohos.multimedia.media';
import common from '@ohos.app.ability.common';
import util from '@ohos.util';

// 播放模式定义
enum PlayMode {
  LIST_LOOP = 0,
  SINGLE_LOOP = 1,
  RANDOM = 2
}

interface LyricLine {
  time: number;
  content: string;
}

@Entry
@Component
struct MusicPlayer {
  private avPlayer: media.AVPlayer | undefined = undefined;
  private scroller: Scroller = new Scroller();

  @State isPlaying: boolean = false;
  @State currentTime: number = 0;
  @State duration: number = 0;
  @State currentLyricIndex: number = 0;
  @State lyricData: LyricLine[] = [];

  // 新增：播放模式状态
  @State playMode: PlayMode = PlayMode.LIST_LOOP;
  private modeIcons: string[] = ['🔂', '🔂 单曲', '🔀 随机']; // 临时用文字代替图标

  async aboutToAppear() {
    await this.initAVPlayer();
    await this.loadLyricResource();
  }

  // 切换播放模式逻辑
  togglePlayMode() {
    if (this.playMode === PlayMode.LIST_LOOP) {
      this.playMode = PlayMode.SINGLE_LOOP;
    } else if (this.playMode === PlayMode.SINGLE_LOOP) {
      this.playMode = PlayMode.RANDOM;
    } else {
      this.playMode = PlayMode.LIST_LOOP;
    }
  }

  async initAVPlayer() {
    try {
      this.avPlayer = await media.createAVPlayer();
      this.setAVPlayerCallback();
      this.loadMusicResource();
    } catch (e) {
      console.error('Init Player Error');
    }
  }

  async loadMusicResource() {
    const player = this.avPlayer;
    if (!player) return;
    let context = getContext(this) as common.UIAbilityContext;
    try {
      let fileDescriptor = await context.resourceManager.getRawFd('test.mp3');
      player.fdSrc = fileDescriptor;
    } catch (e) {
      console.error('Music file not found');
    }
  }

  async loadLyricResource() {
    let context = getContext(this) as common.UIAbilityContext;
    try {
      const value = await context.resourceManager.getRawFileContent('test.lrc');
      let textDecoder = util.TextDecoder.create('utf-8');
      const lrcString = textDecoder.decodeWithStream(value);
      this.parseLrc(lrcString);
    } catch (e) {
      this.lyricData = [{ time: 0, content: "暂无歌词" }];
    }
  }

  parseLrc(lrcContent: string) {
    const lines = lrcContent.split('\n');
    let tempLyrics: LyricLine[] = [];
    const lrcReg = /\[(\d+):(\d+(?:\.\d+)?)\](.*)/;
    lines.forEach(line => {
      const match = line.match(lrcReg);
      if (match) {
        const timeMs = (parseInt(match[1]) * 60 + parseFloat(match[2])) * 1000;
        tempLyrics.push({ time: timeMs, content: match[3].trim() });
      }
    });
    this.lyricData = tempLyrics;
  }

  setAVPlayerCallback() {
    const player = this.avPlayer;
    if (!player) return;
    player.on('stateChange', async (state: string) => {
      const innerPlayer = this.avPlayer;
      if (!innerPlayer) return;
      if (state === 'initialized') innerPlayer.prepare();
      if (state === 'prepared') this.duration = innerPlayer.duration;

      // 新增：播放完成后根据模式自动处理
      if (state === 'completed') {
        if (this.playMode === PlayMode.SINGLE_LOOP) {
          innerPlayer.play(); // 单曲循环直接重播
        } else {
          // 这里以后可以写切歌逻辑
          this.isPlaying = false;
        }
      }
    });
    player.on('timeUpdate', (time: number) => {
      this.currentTime = time;
      this.updateLyricIndex(time);
    });
  }

  updateLyricIndex(time: number) {
    for (let i = this.lyricData.length - 1; i >= 0; i--) {
      if (time >= this.lyricData[i].time) {
        if (this.currentLyricIndex !== i) {
          this.currentLyricIndex = i;
          this.scroller.scrollToIndex(i, true);
        }
        break;
      }
    }
  }

  formatTime(ms: number): string {
    let totalSeconds = Math.floor(ms / 1000);
    return `${Math.floor(totalSeconds / 60).toString().padStart(2, '0')}:${(totalSeconds % 60).toString().padStart(2, '0')}`;
  }

  build() {
    Stack() {
      // 1. 全屏沉浸式背景
      Column().width('100%').height('100%').linearGradient({
        direction: GradientDirection.Bottom,
        colors: [['#1e3799', 0.0], ['#0c2461', 1.0]]
      })

      Column() {
        // 2. 顶部区域
        Stack() {
          Circle().width(200).height(200).fill('#000').shadow({ radius: 25, color: '#000' })
          Image($r('app.media.app_icon'))
            .width(190).height(190).borderRadius(95)
            .rotate({ angle: this.isPlaying ? 360 : 0 })
            .animation({ duration: 8000, iterations: -1, curve: Curve.Linear })
        }
        .margin({ top: 40, bottom: 20 })

        Text("我的音乐作品").fontSize(22).fontWeight(FontWeight.Bold).fontColor(Color.White)

        // 3. 歌词列表
        List({ scroller: this.scroller }) {
          ForEach(this.lyricData, (item: LyricLine, index: number) => {
            ListItem() {
              Text(item.content)
                .width('100%').textAlign(TextAlign.Center)
                .fontSize(this.currentLyricIndex === index ? 22 : 16)
                .fontColor(this.currentLyricIndex === index ? '#ffffff' : '#747d8c')
                .fontWeight(this.currentLyricIndex === index ? FontWeight.Bold : FontWeight.Normal)
                .padding(10)
                .animation({ duration: 300 })
            }
          })
        }.layoutWeight(1).margin({ top: 10, bottom: 10 }).scrollBar(BarState.Off)

        // 4. 底部控制区（修正了重叠问题）
        Column() {
          Slider({ value: this.currentTime, min: 0, max: this.duration <= 0 ? 100 : this.duration })
            .width('95%').blockColor('#fff').selectedColor('#fff')
            .onChange((v, mode) => { if (this.avPlayer && mode === SliderChangeMode.End) this.avPlayer.seek(v); })

          Row() {
            Text(this.formatTime(this.currentTime)).fontSize(12).fontColor('#fff')
            Blank()
            Text(this.formatTime(this.duration)).fontSize(12).fontColor('#fff')
          }.width('90%').margin({ bottom: 10 })

          Row() {
            // 新增：播放模式切换按钮
            Text(this.modeIcons[this.playMode])
              .fontColor(Color.White).fontSize(16)
              .onClick(() => this.togglePlayMode())

            Text('⏮').fontSize(25).fontColor(Color.White)

            Stack() {
              Circle().width(64).height(64).fill('#ffffff').opacity(0.15)
              Text(this.isPlaying ? '⏸' : '▶')
                .fontSize(30).fontColor(Color.White)
                .onClick(() => {
                  if (this.avPlayer) {
                    this.isPlaying ? this.avPlayer.pause() : this.avPlayer.play();
                    this.isPlaying = !this.isPlaying;
                  }
                })
            }

            Text('⏭').fontSize(25).fontColor(Color.White)

            // 占位或更多功能
            Text('⋮').fontColor(Color.White).fontSize(20).opacity(0.8)
          }
          .width('100%').justifyContent(FlexAlign.SpaceAround)
        }
        .width('94%').padding(20).backgroundColor('#22ffffff')
        .borderRadius(25).margin({ bottom: 100 })
      }
      .width('100%').height('100%')
    }
  }
}