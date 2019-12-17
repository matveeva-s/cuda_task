#include <SFML\Graphics.hpp>
#include <iostream>
#include <cmath>
#include <vector>
using namespace std;
struct Point
{
	int x;				  //координата х
	int y;				  //координата у
	sf::Color color;      		  //цвет пикселя
	int number;			  // номер ближайшей центроиды 
};
using Centroids = vector <sf::Color>;
using ClosestCentroidsIndices = vector <Point>;
Centroids initializeCentroids(const sf::Image& image, const int k)
{
	Centroids centroids(k);
	for (int i = 0; i < k; i++)
	centroids[i] = image.getPixel(rand() % image.getSize().x, rand() % image.getSize().y);
	return centroids;
};
ClosestCentroidsIndices findClosestCentroids(const sf::Image& image, Centroids centroids)
{
	ClosestCentroidsIndices points((image.getSize().x)*(image.getSize().y));
	int n = -1;
	for (int i = 0; (i < image.getSize().x); i++)
	{
		for (int j = 0; j < image.getSize().y; j++)
		{
			n++; //текущий номер пикселя
			points[n].x = i;
			points[n].y = j;
			points[n].color = image.getPixel(i, j);
			int min_dist = 200000000;
			for (int k = 0; k < centroids.size(); k++)
			{
				int distance_2 = pow((points[n].color.r - centroids[k].r), 2) + pow((points[n].color.g - centroids[k].g),2) + pow((points[n].color.b - centroids[k].b),2);
				if (distance_2 < min_dist)
				{
					min_dist = distance_2; 
					points[n].number = k;
				}
			}
		}
	}
	return points; 
}
Centroids ComputeMeans(const ClosestCentroidsIndices ids, const int K)
{
	int* num = new int[K];
	int* r = new int[K];
	int* g = new int[K];
	int* b = new int[K];
	Centroids centers(K);
	for (int i = 0; i < K; i++)
	{
		r[i] = 0;
		g[i] = 0;
		b[i] = 0;
		num[i] = 0;
	}
	for (int i = 0; i < ids.size(); i++)
	{
		r[ids[i].number] += (int)ids[i].color.r;
		g[ids[i].number] += (int)ids[i].color.g;
		b[ids[i].number] += (int)ids[i].color.b;
		num[ids[i].number]++;
	}
	for (int i = 0; i < K; i++)
	{
			r[i] /= num[i];
			g[i] /= num[i];
			b[i] /= num[i];
			centers[i].r = r[i];
			centers[i].g = g[i];
			centers[i].b = b[i];
	}
	for (int i = 0; i < K; i++)
	{
		centers[i].r = r[i];
		centers[i].g = g[i];
		centers[i].b = b[i];
	}
	delete[]num;
	delete[]r;
	delete[]g;
	delete[]b;
	return centers;
}
void ChangeColors(sf::Image& image, ClosestCentroidsIndices ids, Centroids centroids)
{
	for (int i = 0; i < ids.size(); i++)
		image.setPixel(ids[i].x, ids[i].y, centroids[ids[i].number]);
}

int main()
{
	int K = 3; //количество цветов
	int IterationCount = 20; 
	sf::Image im;
	sf::Texture texture;
	sf::Sprite photo;
	// откуда грузится файл
	texture.loadFromFile("file.png");
	auto image = texture.copyToImage();
	
	ClosestCentroidsIndices ids;
	Centroids centroids = initializeCentroids(image, K);
	for (int it = 0; it < IterationCount; it++)
	{
		ids = findClosestCentroids(image, centroids);
		centroids = ComputeMeans(ids, K);
	}
	ChangeColors(image, ids, centroids);
	// куда сохраняется файл
	image.saveToFile("result.png");
	texture.update(image);
	photo.setTexture(texture);
	system("pause");
}



