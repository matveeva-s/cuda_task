#include<stdlib.h>
#include<iostream>
#include <SFML/Graphics.hpp>

#define K 10
#define IC 1000
#define BLOCK_SIZE 16
#define NUM_THREADS 100

struct Point
{
    //coordinates
    int x;
    int y;
    //color
    int r;
    int g;
    int b;
    //centroids number
    int number;
};
struct Centroid
{
    int r;
    int g;
    int b;
};

struct Matrix
{
    int x;
    int y;
    Centroid * elements;
};


Centroid* initializeCentroids(Matrix image)
{
    Centroid* centroids = (Centroid*)malloc(sizeof(Centroid)*K);
    for (int i = 0; i < K; i++)
        centroids[i] = image.elements[(rand() % image.x)*image.y + (rand() % image.y)];
    return centroids;
};


__global__ void findClosestCentroids_cuda(Matrix image, Centroid* centroids, Point* res,int start_x = 0 ,int start_y = 0)
{

    int col = blockIdx.x * blockDim.x + threadIdx.x + start_x;
    int row =  blockIdx.y * blockDim.y + threadIdx.y + start_y;

    int n = col* image.y + row; //текущий номер пикселя
    res[n].x = col;
    res[n].y = row;
    res[n].r = image.elements[n].r;
    res[n].g = image.elements[n].g;
    res[n].b = image.elements[n].b;
    int min_dist = 200000000;
    for (int k = 0; k < K; k++)
    {
        int distance_2 = (res[n].r - centroids[k].r) * (res[n].r - centroids[k].r)
            + (res[n].g - centroids[k].g) * (res[n].g - centroids[k].g)
            + (res[n].b - centroids[k].b) * (res[n].b - centroids[k].b);
        if (distance_2 < min_dist)
        {
            min_dist = distance_2;
            res[n].number = k;
        }
    }
}

__global__ void ComputeMeans_cuda(const Point* ids, int imsize, Centroid* res)
{
    __shared__ int num[K*NUM_THREADS];
    __shared__ int r[K*NUM_THREADS];
    __shared__ int g[K*NUM_THREADS];
    __shared__ int b[K*NUM_THREADS];
    int id = threadIdx.x;
    for (int i = 0; i < K; i++)
    {
        r[i+id*K] = 0;
        g[i+id*K] = 0;
        b[i+id*K] = 0;
        num[i+id*K] = 0;
    }
    int block_size = imsize/NUM_THREADS;

    for (int i = block_size*id; i < block_size*(id+1); i++)
    {
        r[ids[i].number + id*K] += (int)ids[i].r;
        g[ids[i].number + id*K] += (int)ids[i].g;
        b[ids[i].number + id*K] += (int)ids[i].b;
        num[ids[i].number + id*K]++;
    }
    if (0 == id)
    {
        for (int i = block_size*NUM_THREADS; i < imsize; i++)
        {
            r[ids[i].number + id*K] += (int)ids[i].r;
            g[ids[i].number + id*K] += (int)ids[i].g;
            b[ids[i].number + id*K] += (int)ids[i].b;
            num[ids[i].number + id*K]++;
        }
    }
    __syncthreads();
    if (0 == id)
    {
        for (int i = 1; i < NUM_THREADS; i++)
        {
            for (int j = 0; j < K; j++)
            {
                r[j] += r[j+i*K];
                g[j] += g[j+i*K];
                b[j] += b[j+i*K];
                num[j] += num[j+i*K];
            }
        }
        for (int i = 0; i < K; i++)
        {
            r[i] /= num[i];
            g[i] /= num[i];
            b[i] /= num[i];
            res[i].r = r[i];
            res[i].g = g[i];
            res[i].b = b[i];
        }
    }

}

__global__ void ChangeColors_cuda(Matrix image, Point*  ids, Centroid* centroids,int start_x =0, int start_y = 0)
{
    int col = blockIdx.x * blockDim.x + threadIdx.x + start_x;
    int row =  blockIdx.y * blockDim.y + threadIdx.y + start_y;
    int n = col* image.y + row; //текущий номер пикселя
    image.elements[ids[n].x* image.y + ids[n].y] = centroids[ids[n].number];
}

int main(void)
{
    //loading picture using sfml
    sf::Image im;
    sf::Texture texture;
    sf::Sprite photo;
    texture.loadFromFile("/home/cuda/file.png");
    sf::Image image_sf = texture.copyToImage();
    // prepare host data
    int x = image_sf.getSize().x;
    int y = image_sf.getSize().y;
    Matrix image;
    image.x =x;
    image.y= y;
    image.elements = (Centroid*)malloc(sizeof(Centroid)*x*y);

    for (int i = 0 ; i < x ; i ++)
    {
        for (int j = 0 ; j < y; j++)
        {
            sf::Color pix = image_sf.getPixel(i,j);
            image.elements[i* image.y + j].r = pix.r;
            image.elements[i* image.y + j].g = pix.g;
            image.elements[i* image.y + j].b = pix.b;
        }
    }

    Centroid* centroids = initializeCentroids(image);

    // prepare device data
    Matrix image_cuda;
    image_cuda.x = image.x;
    image_cuda.y = image.y;

    Centroid* centroids_cuda;

    cudaMalloc(&centroids_cuda,sizeof(Centroid)*K);
    cudaMalloc(&image_cuda.elements,sizeof(Centroid)*x*y);

    cudaMemcpy(centroids_cuda,centroids, sizeof(Centroid)*K,cudaMemcpyHostToDevice);
    cudaMemcpy(image_cuda.elements,image.elements,sizeof(Centroid)*x*y,cudaMemcpyHostToDevice);

    Point* ids_cuda;
    cudaMalloc(&ids_cuda,image.x*image.y*sizeof(Point));

    dim3 dimBlock(BLOCK_SIZE, BLOCK_SIZE);
    dim3 dimGrid(image_cuda.x / dimBlock.x, image_cuda.y / dimBlock.y);

    dim3 dimBlockE1(image_cuda.x % dimBlock.x, image_cuda.y % dimBlock.y);
    dim3 dimGridE1(1,1);
    if (0 != dimBlockE1.y)
        dimGridE1 = dim3(1, image_cuda.y/dimBlockE1.y);

    dim3 dimBlockE2(image_cuda.x % dimBlock.x, image_cuda.y % dimBlock.y);
    dim3 dimGridE2(1,1);
    if (0 != dimBlockE2.x)
        dimGridE2 = dim3(image_cuda.x/dimBlockE2.x, 1);
    // process
    for (int it = 0; it < IC; it++)
    {
        findClosestCentroids_cuda<<<dimGrid, dimBlock>>>(image_cuda, centroids_cuda, ids_cuda);
        //Edges we process separately
        if (0 != dimBlockE1.y)
        {
            findClosestCentroids_cuda <<< dimGridE1, dimBlockE1 >>> (image_cuda, centroids_cuda, ids_cuda,
                image_cuda.x - image_cuda.x % dimBlock.x,
                0);
        }
        if (0 != dimBlockE2.x)
        {
            findClosestCentroids_cuda <<< dimGridE2, dimBlockE2 >>> (image_cuda, centroids_cuda, ids_cuda,
                0,
                image_cuda.y - image_cuda.y % dimBlock.y);
        }

        ComputeMeans_cuda<<<1,NUM_THREADS>>>(ids_cuda,x*y,centroids_cuda);

    }
    ChangeColors_cuda<<<dimGrid, dimBlock>>>(image_cuda,ids_cuda,centroids_cuda);
    //Edges we process separately
    if (0 != dimBlockE1.y)
    {
        ChangeColors_cuda << < dimGridE1, dimBlockE1 >> > (image_cuda, ids_cuda, centroids_cuda,
            image_cuda.x - image_cuda.x % dimBlock.x,
            0);
    }
    if (0 != dimBlockE2.x)
    {
        ChangeColors_cuda <<< dimGridE2, dimBlockE2 >>> (image_cuda, ids_cuda, centroids_cuda,
            0,
            image_cuda.y - image_cuda.y % dimBlock.y);
    }

    cudaMemcpy(image.elements,image_cuda.elements,sizeof(Centroid)*x*y,cudaMemcpyDeviceToHost);
    cudaFree(centroids_cuda);
    cudaFree(image_cuda.elements);
    cudaFree(ids_cuda);

    //return data to sfml format
    for (int i = 0 ; i < x ; i ++)
    {
        for (int j = 0 ; j < y; j++)
        {
            image_sf.setPixel(i,j,sf::Color( image.elements[i* image.y + j].r,
                                             image.elements[i* image.y + j].g,
                                             image.elements[i* image.y + j].b));
        }
    }

    image_sf.saveToFile("/home/cuda/result.png");
    texture.update(image_sf);
    photo.setTexture(texture);
}



