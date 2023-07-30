#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include "fatfs/ff.h"
#include "fatfs/diskio.h"
#include "fatfs/spi.h"
#include "common.h"
#include "fileio.h"
#include <string.h>

// a pointer to this is a null pointer, but the compiler does not
// know that because "sram" is a linker symbol from sections.lds.
extern uint32_t sram;

typedef struct {
    volatile uint32_t DATA;
    volatile uint32_t CLKDIV;
} PICOUART;

typedef struct {
    volatile uint32_t OUT;
    volatile uint32_t IN;
    volatile uint32_t OE;
} PICOGPIO;

typedef struct {
    union {
        volatile uint32_t REG;
        volatile uint16_t IOW;
        struct {
            volatile uint8_t IO;
            volatile uint8_t OE;
            volatile uint8_t CFG;
            volatile uint8_t EN; 
        };
    };
} PICOQSPI;

typedef struct {
    volatile uint32_t START;
    volatile uint32_t STOP;
    volatile uint32_t START_ADDR;
    volatile uint32_t FLAG_RD;
    volatile uint32_t FLAG_WR;
    volatile uint32_t DUMMY;
} HDMIREG;

typedef struct {
    volatile uint32_t CTRL;
    volatile uint32_t WB_SADR;
    volatile uint32_t WB_EADR;
    volatile uint32_t DUMMY0;
    volatile uint32_t timerl;
    volatile uint32_t timerh;
    volatile uint32_t DUMMY1;
    volatile uint32_t DUMMY2;
    volatile uint32_t acc_cnt;
    volatile uint32_t whit_cnt;
    volatile uint32_t rhit_cnt; // 0x28
    volatile uint32_t DUMMY3;   // 0x2c
    volatile uint32_t fifo_wadrs;   // 0x30
    volatile uint32_t fifo_warea;   // 0x34
    volatile uint32_t fifo_wdata;   // 0x38
    volatile uint32_t fifo_ctl;     // 0x3c
} CACHEREG;

#define QSPI0 ((PICOQSPI*)0x81000000)
#define GPIO0 ((PICOGPIO*)0x82000000)
#define UART0 ((PICOUART*)0x83000000)
#define HDMIREG ((HDMIREG*)0x85000000)
#define CACHEREG ((CACHEREG*)0x86000000)
// PSRAM 8MB
// 0xc000_0000 - 0xc07F_FFFF
#define PSRAM_ADDR (0xc0000000)


#define FLASHIO_ENTRY_ADDR ((void *)0x80000054)

void (*spi_flashio)(uint8_t *pdata, int length, int wren) = FLASHIO_ENTRY_ADDR;

// for fat test
char  sbuff[64];
#define DEF_FATBUFF  1024
char  buff_fat[ DEF_FATBUFF ];
char file_name[10][64];     // 最大file数=10


int putchar(int c)
{	
    if (c == '\n')
        UART0->DATA = '\r';
    UART0->DATA = c;
    
    return c;
}

volatile void print(const char *p)
{
    while (*p)
        putchar(*(p++));
}

void print_hex(uint32_t v, int digits)
{
    for (int i = 7; i >= 0; i--) {
        char c = "0123456789abcdef"[(v >> (4*i)) & 15];
        if (c == '0' && i >= digits) continue;
        putchar(c);
        digits = i;
    }
}

void print_dec(uint32_t v)
{
    if (v >= 100) {
        print(">=100");
        return;
    }

    if      (v >= 90) { putchar('9'); v -= 90; }
    else if (v >= 80) { putchar('8'); v -= 80; }
    else if (v >= 70) { putchar('7'); v -= 70; }
    else if (v >= 60) { putchar('6'); v -= 60; }
    else if (v >= 50) { putchar('5'); v -= 50; }
    else if (v >= 40) { putchar('4'); v -= 40; }
    else if (v >= 30) { putchar('3'); v -= 30; }
    else if (v >= 20) { putchar('2'); v -= 20; }
    else if (v >= 10) { putchar('1'); v -= 10; }

    if      (v >= 9) { putchar('9'); v -= 9; }
    else if (v >= 8) { putchar('8'); v -= 8; }
    else if (v >= 7) { putchar('7'); v -= 7; }
    else if (v >= 6) { putchar('6'); v -= 6; }
    else if (v >= 5) { putchar('5'); v -= 5; }
    else if (v >= 4) { putchar('4'); v -= 4; }
    else if (v >= 3) { putchar('3'); v -= 3; }
    else if (v >= 2) { putchar('2'); v -= 2; }
    else if (v >= 1) { putchar('1'); v -= 1; }
    else putchar('0');
}

#define QSPI_REG_CRM  0x00100000
#define QSPI_REG_DSPI 0x00400000

void cmd_set_crm(int on)
{
    if (on) {
        QSPI0->REG |= QSPI_REG_CRM;
    } else {
        QSPI0->REG &= ~QSPI_REG_CRM;
    }
}

int cmd_get_crm() {
    return QSPI0->REG & QSPI_REG_CRM;
}

void cmd_set_dspi(int on)
{
    if (on) {
        QSPI0->REG |= QSPI_REG_DSPI;
    } else {
        QSPI0->REG &= ~QSPI_REG_DSPI;
    }
}

int cmd_get_dspi() {
    return QSPI0->REG & QSPI_REG_DSPI;
}

//volatile int i;
// --------------------------------------------------------

//#define CLK_FREQ        25175000
#define CLK_FREQ        37125000
#define UART_BAUD       115200

int  fat_test_init( void )
{
    DSTATUS  ret;
    int  result = 0;

    ret = disk_initialize( 0 );
    if( ret & STA_NOINIT ) {
        result = -1;
    }

    return  result;
}



//FRESULT scan_files (
int scan_files (
    char* path,        /* Start node to be scanned (***also used as work area***) */
    int start_filenum,
    char file_name[][64], int maxnum,
    int *ret_file_num
)
{
    FATFS fs;
    FRESULT res;
    FILINFO fno;
    DIR dir;
    int i;
    char *fn;   /* 非Unicode構成を想定 */
#if _USE_LFN
    static char lfn[_MAX_LFN + 1];
    fno.lfname = lfn;
    fno.lfsize = sizeof lfn;
#endif

    int file_num=start_filenum;
    int file_name_pos;

    res = f_opendir(&dir, path);                       /* ディレクトリを開く */
    if(res == FR_OK) {
        i = strlen(path);
        for (;;) {
            //DEBUG_LOG(sbuff,"file_num=%d\n",file_num);
            res = f_readdir(&dir, &fno);                   /* Read a directory item */
            if (res != FR_OK || fno.fname[0] == 0) {
                print("Err: illegal filename\n");
                break;  /* Break on error or end of dir */
            }
            if (fno.fname[0] == '.') continue;             /* ドットエントリは無視 */
#if _USE_LFN
            fn = *fno.lfname ? fno.lfname : fno.fname;
#else
            fn = fno.fname;
#endif
            if (fno.fattrib & AM_DIR) {                    /* It is a directory */
                sprintf(&path[i], "/%s", fn);
                res = scan_files(path,file_num, file_name,10, &file_num);
                if (res != FR_OK) break;
                path[i] = 0;
            } else {                                       /* It is a file. */
                //sprintf(sbuff, "%d) %s\n", file_num,fno.fname);
                //print(sbuff);
                // strcatの代わり
                sprintf(file_name[file_num],"%s/%s",path,fno.fname);
                //sprintf(sbuff, "%s\n", file_name[file_num]);
                //print(sbuff);
                file_num++;
                if(file_num==maxnum) {
                    print("reached max file num.\n");
                    *ret_file_num = file_num-1;
                    return res;
                }
            }

            //f_closedir(&dir);
        }
    }
    *ret_file_num = file_num;
    return res;
}


void chg_888_to_565_2pix(
    char *buff_rpt,  int pixnum
)
{
    // RGB565作成
    int i;
    int r8,g8,b8;
    unsigned char gh3,gl3;
    int r82,g82,b82;
    unsigned char gh32,gl32;
    uint32_t wr_pix2;
    
    for(i=0 ; i<pixnum/2; i++) {
        // BMP : BGR
        b8 = *buff_rpt++;
        g8 = *buff_rpt++;
        r8 = *buff_rpt++;
        b82 = *buff_rpt++;
        g82 = *buff_rpt++;
        r82 = *buff_rpt++;
        //DEBUG_LOG(sbuff,"BGR=%x,%x,%x, adr=%x\n",b8,g8,r8,buff_rpt-3);
        gh3=((g8&0xe0)>>5);       // VAL=LSB3
        gl3=((g8&0x1c)>>2);       // val=LSB3
        b8 = (b8>>3);   // val=LSB5
        gh32=((g82&0xe0)>>5);       // VAL=LSB3
        gl32=((g82&0x1c)>>2);       // val=LSB3
        b82 = (b82>>3);   // val=LSB5
        //DEBUG_LOG(sbuff,"wpt=%x\n",wpt);
        //*wpt++ = ((gl3)<<5) | (b8&0x1f);
        //*wpt++ = (r8&(0xf8))|gh3;
        wr_pix2 = ((gl3)<<5) | (b8&0x1f) | (( (r8&(0xf8))|gh3 ) << 8);
        wr_pix2 += ((((gl32)<<5) | (b82&0x1f) |
                    (( (r82&(0xf8))|gh32 ) << 8))<<16);
        //*wpt++ = wr_pix2;
        CACHEREG->fifo_wdata = wr_pix2;
    }


}

void disp_cache_timer()
{
    // free run timer read
    unsigned int free_timer_l;
    unsigned int free_timer_h;
    unsigned int free_timer_h2;

    free_timer_l=CACHEREG->timerl;
    free_timer_h=CACHEREG->timerh;
    free_timer_h2=CACHEREG->timerh;
    if(free_timer_h != free_timer_h2) {
        // 上位が更新されたので、下位を読みだす
        free_timer_l = CACHEREG->timerl;
    }
    //long_timer = (free_timer_h<<32)+free_timer_l;
    DEBUG_LOG(sbuff,"*** timer value=%x_%x ***\n",free_timer_h2,free_timer_l);

}


void vram_init (
    uint32_t initdata, int pixnum
)
{
    uint32_t init_2pix;
    int i;
    // 16bitデータを32bitへ並べる(2pix/32bitにする）
    init_2pix = ((initdata<<16) | initdata);
    //開始時刻表示
    print("Start vram init: ");
    disp_cache_timer();
    for(i=0; i< ((pixnum*2)/4); i++)
        CACHEREG->fifo_wdata=0;
    //終了時刻表示
    print("End vram init: ");
    disp_cache_timer();
    
}

// bmpファイルをVRAMへ
void copy_to_vram(int in_xsize, int in_ysize, int OffBits, FIL* fil)
{
    FRESULT  sd_ret;
    
    // PSRAMへRGB565へ変換と同時に書き込んでいく(320pix)
    // 水平サイズ分が4の倍数になるようにstuff考慮
    int stuff_byte;
    int h_split_cnt;
    int h_split_last;
    int h_cnt;
    int v_cnt;
    
    UINT rdsz;

    stuff_byte = (in_xsize*3)%4;
    h_split_cnt = in_xsize/320;
    h_split_last = in_xsize%320;
    if(h_split_last) h_split_cnt++;
    //DEBUG_LOG(sbuff,"START_ADDR=%x\n",HDMIREG -> START_ADDR);
    //DEBUG_LOG(sbuff,"stuff_byte=%d, h_split_cnt=%d, h_split_last=%d\n"
    //    ,stuff_byte,h_split_cnt,h_split_last);

    //開始時刻表示
    print("Start write image to vram. ");
    disp_cache_timer();

    for(v_cnt=0; v_cnt<in_ysize; v_cnt++) {
        f_lseek(fil, OffBits+(in_xsize*(in_ysize-v_cnt-1)*3));
        //  2byte = 1pix なので/2
        //image_wpt = image_top + (in_xsize/2)*(in_ysize-(v_cnt+1));
        //DEBUG_LOG(sbuff,"v_cnt=%d, image_wpt=%x\n",v_cnt,image_wpt);
        //DEBUG_LOG(sbuff,"v_cnt=%d\n",v_cnt);
        for(h_cnt=0; h_cnt<h_split_cnt; h_cnt++) {
            // 水平端関係なく常に320pix=960byteロード
            SPI_SD->debug=0x2;     //ロジアナへトリガ信号
            sd_ret = f_read( fil, buff_fat, 320*3,  &rdsz);
            if(h_cnt == (h_split_cnt-1)) { // last回
                //chg_888_to_565_2pix(buff_fat,image_wpt,(h_split_last==0)?320:h_split_last);
                chg_888_to_565_2pix(buff_fat,
                    (h_split_last==0) ? 320 : h_split_last);
            }
            else {
                //chg_888_to_565_2pix(buff_fat,image_wpt,320);// 320pix処理
                chg_888_to_565_2pix(buff_fat,320);// 320pix処理
                //image_wpt += (320/2);   // +1 で4byte
            }
        }
    }
    print("End write image to vram. ");
    disp_cache_timer();
    print("\n");
}


int main()
{
    int fatfs_ret;
    int  wsize;
    FIL fil;
    UINT rdsz;
    char *buff_fat_pt;
    
    UART0->CLKDIV = CLK_FREQ / UART_BAUD - 2;

    GPIO0->OE = 0x3F;
    GPIO0->OUT = 0x3F;

    cmd_set_crm(1);
    cmd_set_dspi(1);

    print("\n");
    print("  ____  _          ____         ____\n");
    print(" |  _ \\(_) ___ ___/ ___|  ___  / ___|\n");
    print(" | |_) | |/ __/ _ \\___ \\ / _ \\| |\n");
    print(" |  __/| | (_| (_) |__) | (_) | |___\n");
    print(" |_|   |_|\\___\\___/____/ \\___/ \\____|\n");
    print("\n");
    print("        On Lichee Tang Nano-9K\n");
    print("This is modified firmware. add SD access.\n");
    print("\n");



// SD card

    fatfs_ret = fat_test_init();
    //print("kita\n");
    if( fatfs_ret != 0 ) {
        print("fat_test_init()  ERROR!\n" );
    }

    //fatfs_ret = scan_files();
    volatile uint32_t *PSRAM;
    PSRAM = (uint32_t*) PSRAM_ADDR;

    FRESULT  sd_ret;
    FATFS  sd_fs;
    buff_fat_pt = &buff_fat[0];
    
    // SDカードマウント
    sd_ret = f_mount( &sd_fs, "", 0 );
    if( sd_ret != FR_OK ) {
        DEBUG_LOG(sbuff,"ERROR(%d): f_mount\n",sd_ret);
        //print( sbuff );
        return  -1;
    }
    
    // fifoアクセスモード初期設定
    CACHEREG->fifo_wadrs = PSRAM_ADDR;  //start adrs
    CACHEREG->fifo_warea = 1280 * 720 *2 ; // frame size in byte
    CACHEREG->fifo_ctl = 1; // fifo mode start
    
    // vram 初期化 RGB565(16bit/pixel)
    vram_init(0, 1280*720);

    // HDMI スタート
    // HDMI ON
    HDMIREG -> START_ADDR = PSRAM_ADDR+0;
    HDMIREG -> START=1;
    HDMIREG -> STOP=0;

    // bmp dir内サーチ
    // 1280x720 bmpのみを検索する
    // file_name[]にbmpのファイル名が格納される
    char file_name[10][64];     // 最大file数=10
    int file_num;
    scan_files("bmp", 0, file_name,10, &file_num);
    if(file_num==0) {
        print("it is nothing bmp file.\n");
        return 0;
    }
    //return 0;

	int	OffBits;
    int aligned_hsize;
	int hsize;
	int in_xsize;
	int in_ysize;
    while(1) {
        for(int picno=0; picno<file_num; picno++) {
            // ファイルオープン
            sd_ret = f_open( &fil, file_name[picno], FA_READ );
            if( sd_ret != FR_OK ) {
                DEBUG_LOG(sbuff,"ERROR(%d): f_open\n",sd_ret);
                return  -1;
            }
            DEBUG_LOG(sbuff,"filename: %s\n",file_name[picno]);
            // ファイル読み出し 1KBづつ
            // buff_fat: バッファー
            // DEF_FATBUFF : 読みだすバイト数=1024
            // &rdsz : 読みだせたバイト数
            sd_ret = f_read( &fil, buff_fat, DEF_FATBUFF,  &rdsz);
            // BMP情報の取り出し
            OffBits = BMP_analysis(buff_fat_pt, &in_xsize, &in_ysize);
            if(OffBits<0) continue; // not bmp or not 24bit color
            if( (in_xsize!=1280) | (in_ysize!=720)) continue;   // サイズ外
            
            // bmpファイルをVRAMへ
            copy_to_vram(in_xsize,in_ysize,OffBits,&fil);
        }
    }


}


void irqCallback() {

}
