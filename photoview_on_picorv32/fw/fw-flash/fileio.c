#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include "fileio.h"
#include "common.h"

extern void     print(const char *p);
extern char     sbuff[64];

int Get2Bytes(char *fp)
{
	int     ret;

	ret = *fp;
	fp++;
    ret += ((*fp)<<8);
	return(ret);
}

int Get4Bytes(char *fp)
{
	int     ret;

	ret = *fp;
	fp++;
	ret += ((*fp)<<8);
	fp++;
	ret += ((*fp)<<16);
	fp++;
	ret += ((*fp)<<24);
	return(ret);
}

/* 入力BMPファイルの解析 */
int BMP_analysis(char *buff_fat_pt, int *xsize, int *ysize)
{
	int	OffBits;
	int hsize;
	int BitCount;

    buff_fat_pt+=0x0a;      // OffBitsへ
    OffBits = Get4Bytes(buff_fat_pt);
    buff_fat_pt+=4;
	hsize = Get4Bytes(buff_fat_pt);
    buff_fat_pt+=4;
	if (hsize != 40) {
		print("is not BMP FILE.\n");
		return  -1;
	}
	*xsize = Get4Bytes(buff_fat_pt);
	buff_fat_pt+=4;
	*ysize = Get4Bytes(buff_fat_pt);
    buff_fat_pt+=4;
    DEBUG_LOG(sbuff,"xsize=%d, ysize=%d\n", *xsize,*ysize);
    
	Get2Bytes(buff_fat_pt);                     /*dummy Planes */
    buff_fat_pt+=2;

	BitCount = Get2Bytes(buff_fat_pt);
	buff_fat_pt+=2;
	if (BitCount != 24) {
	    DEBUG_LOG(sbuff,"is not 24bit depth color.BitCount=%d\n", BitCount);
		return  -1;
	}


	return OffBits;

}

