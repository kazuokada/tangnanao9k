#pragma once
#include <stdio.h>


int Get2Bytes(char *fp);
int Get4Bytes(char *fp);
int BMP_analysis(char *fpi, int *xsize, int *ysize);
//void Load_bmp(unsigned char *srcp,char *filename, int *in_xsize, int *in_ysize);
