//
//  main.c
//  imDetector
//
//  Created by KylinHuang on 13-09-22.
//  Copyright (c) 2013年 KylinHuang. All rights reserved.
//

#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdarg.h>

#define PNG_DEBUG 3
#include <png.h>

void abort_(const char * s, ...)
{
    va_list args;
    va_start(args, s);
    vfprintf(stderr, s, args);
    fprintf(stderr, "\n");
    va_end(args);
    abort();
}

int x, y;

int width, height;
png_byte color_type;
png_byte bit_depth;

png_structp png_ptr;
png_infop info_ptr;
int number_of_passes;
png_bytep * row_pointers;

void read_png_file(char* file_name)
{
    char header[8];    // 8 is the maximum size that can be checked
    
    /* open file and test for it being a png */
    FILE *fp = fopen(file_name, "rb");
    if (!fp)
        abort_("[read_png_file] File %s could not be opened for reading", file_name);
    fread(header, 1, 8, fp);
    if (png_sig_cmp((const png_byte*)header, 0, 8))
        abort_("[read_png_file] File %s is not recognized as a PNG file", file_name);
    
    /* initialize stuff */
    png_ptr = png_create_read_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
    
    if (!png_ptr)
        abort_("[read_png_file] png_create_read_struct failed");
    
    info_ptr = png_create_info_struct(png_ptr);
    if (!info_ptr)
        abort_("[read_png_file] png_create_info_struct failed");
    
    if (setjmp(png_jmpbuf(png_ptr)))
        abort_("[read_png_file] Error during init_io");
    
    png_init_io(png_ptr, fp);
    png_set_sig_bytes(png_ptr, 8);
    
    png_read_info(png_ptr, info_ptr);
    
    width = png_get_image_width(png_ptr, info_ptr);
    height = png_get_image_height(png_ptr, info_ptr);
    color_type = png_get_color_type(png_ptr, info_ptr);
    bit_depth = png_get_bit_depth(png_ptr, info_ptr);
    
    number_of_passes = png_set_interlace_handling(png_ptr);
    png_read_update_info(png_ptr, info_ptr);
    
    
    /* read file */
    if (setjmp(png_jmpbuf(png_ptr)))
        abort_("[read_png_file] Error during read_image");
    
    row_pointers = (png_bytep*) malloc(sizeof(png_bytep) * height);
    for (y=0; y<height; y++)
        row_pointers[y] = (png_byte*) malloc(png_get_rowbytes(png_ptr,info_ptr));
    
    png_read_image(png_ptr, row_pointers);
    
    fclose(fp);
}

void clean()
{
    for (y=0; y<height; y++)
        free(row_pointers[y]);
    free(row_pointers);
}

int decide_color(int r, int b, int diffrence)
{
    if (r >= b && r - b > diffrence)
    {
        return 0;
    } else {
        return 1;
    }
}

int get_color(int x, int y, int d)
{
    png_byte* row = row_pointers[y];
    if (png_get_color_type(png_ptr, info_ptr) == PNG_COLOR_TYPE_RGB)
    {
        png_byte* ptr = &(row[x*3]);
        //printf("Pixel at position [ %d - %d ] has RGB values: %d - %d - %d\n", x, y, ptr[0], ptr[1], ptr[2]);
        return decide_color((int)ptr[0], (int)ptr[2], d);
    }
    else if (png_get_color_type(png_ptr, info_ptr) == PNG_COLOR_TYPE_RGBA)
    {
        png_byte* ptr = &(row[x*4]);
        //printf("Pixel at position [ %d - %d ] has RGBA values: %d - %d - %d - %d\n", x, y, ptr[0], ptr[1], ptr[2], ptr[3]);
        return decide_color((int)ptr[0], (int)ptr[2], d);
    }
    else
    {
        abort_("[process_file] color_type of input file must be PNG_COLOR_TYPE_RGBA (%d) (is %d)",
               PNG_COLOR_TYPE_RGBA, png_get_color_type(png_ptr, info_ptr));
        return -1;
    }
}

int rows()
{
    return (int)(height / 20);
}

int columns()
{
    return (int)(width / 118);
}

void detect(int n, int d)
{
    int index, pos_row, pos_column;
    int i, j;
    int pos_pixel_x[5] = {13, 32, 49, 78, 107}, pos_pixel_y[2] = {8, 20};
    int num_columns = columns();
    int sum_num, result;
    for (index = 0, pos_row = 0, pos_column = 0; index < n; ++index, ++pos_column)
    {
        if (pos_column == num_columns)
        {
            pos_column = 0;
            pos_row += 1;
        }
        sum_num = 0;
        for (i = 0; i < 5; ++i)
        {
            for (j = 0; j < 2; ++j)
            {
                result = get_color(pos_pixel_x[i] + pos_column * 118, pos_pixel_y[j] + pos_row * 20, d);
                if (result != 0 && result != 1)
                {
                    printf("ERROR\n");
                    return;
                }
                sum_num += result;
            }
        }
        if (sum_num <= 2) {
            printf ("0\n");
        } else if (sum_num >= 9) {
            printf ("1\n");
        } else {
            printf ("ERROR\n");
            return;
        }
    }
    //printf ("\n");
}


int main(int argc, char **argv)
{
    if (argc != 4)
        abort_("Usage: program_name <file_in> <num> <red_blue_diffrence>");
    
    read_png_file(argv[1]);
    detect(atoi(argv[2]), atoi(argv[3]));
    clean();
    return 0;
}