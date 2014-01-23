#!/opt/local/bin/python2.7

import argparse
import json
import numpy as np
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d import Axes3D
from matplotlib import cm
from pylab import scatter, title, plot, colorbar, setp, get, gca, axis, arange, imshow, contour, contourf
import random

def main():
    '''Plot a surfaces defined in a JSON file
    
    Typical use: 
    
    tfitsurf -n 1 X_IMAGE Y_IMAGE FWHM_IMAGE  < sub.cat > sub.json
    jsurfplot sub.json
    
    '''
    parser = argparse.ArgumentParser()
    parser.add_argument("input_file",help="Input JSON file containing the surface");
    parser.add_argument("-o","--output_file", help="Output file name")
    parser.add_argument("-n","--number_format", help="Number format for contours", default = '%1.1f')
    parser.add_argument("-p","--points", help="Plot data points", action="store_true")
    parser.add_argument("-T","--type", type=int, default=1, help="Type of plot (1=image, 2=surface)")
    parser.add_argument("-t","--title", help="Title of the plot")
    parser.add_argument("-l","--lower", type=float, help="Lower limit to plot range")
    parser.add_argument("-u","--upper", type=float, help="Upper limit to plot range")
    parser.add_argument("-X", type=int, default=3352, help="Number of X pixels")
    parser.add_argument("-Y", type=int, default=2532, help="Number of Y pixels")
    parser.add_argument("-v","--verbose", help="Increase output verbosity", action="store_true")
    parser.add_argument("-m","--mean", help="Display mean in the title", action="store_true")
    parser.add_argument("-C","--contour", help="Draw labeled contours", action="store_true")
    args = parser.parse_args()

    nx = args.X
    ny = args.Y
    points = args.points
    number_format = args.number_format
    verbose = args.verbose
    plottype = args.type
    thetitle = args.title
    drawcontours = args.contour
    input_file = args.input_file
    output_file = args.output_file
    lower = args.lower
    upper = args.upper
    showmean = args.mean

    'Get data from JSON file'
    json_data = open(input_file)
    data = json.load(json_data)
    equation = data['equation']
    labels = data['axes']
    json_data.close()

    def fun(x,y):
        return eval(equation)

    'Define the color map'
    cmap=cm.Spectral

    'Image plot'
    if (plottype == 1):
        x = np.arange(1, nx, 20)
        y = np.arange(1, ny, 20)
        X, Y = np.meshgrid(x, y)
        zs = np.array([fun(x,y) for x,y in zip(np.ravel(X), np.ravel(Y))])
        Z = zs.reshape(X.shape)

        fig = plt.figure(figsize=(7,4.5))
        fig.subplots_adjust(hspace = 0.15, wspace = 0, top=0.95, bottom=0.07, left=0.14, right=0.98)
        ax = fig.add_subplot(111)

        extent = (1,nx,1,ny)

        if (not lower):
            lower = Z.min()
        if (not upper):
            upper = Z.max()
        norm = cm.colors.Normalize(vmax=upper, vmin=lower)
        im = imshow(Z, interpolation='nearest', extent=extent, cmap=cmap, norm=norm)
        ax.set_xlabel(labels[0])
        ax.set_ylabel(labels[1])
        if (thetitle):
            if (showmean):
                thetitle = "%s (Mean: %.2f)" % (thetitle,np.mean(Z))
            title(thetitle);

        'Plot the data points'
        if (points):
            xs = data['xdata']
            ys = data['ydata']
            scatter(xs,ys,s=5,marker='.',color='b')

        'Plot the contours'
        if (drawcontours):
            dz = (Z.max() - Z.min())/6
            levels = arange(Z.min(),Z.max(),dz)
            cplot = contour(Z, levels, hold='on', colors = 'k', extent=extent, linewidth=0.1, origin='image')
            plt.clabel(cplot, inline=2, fmt=number_format, use_clabeltext=True, fontsize=10, origin='image')

        'Plot the color bar'
        ylim = get(gca(), 'ylim')
        setp(gca(), ylim=ylim[::-1])
        cbar=colorbar(im, shrink=0.7,aspect=15)
        cbar.ax.set_ylabel(labels[2], rotation=90)

    'Surface plot'
    if (plottype == 2):
        fig = plt.figure()
        ax = fig.add_subplot(111, projection='3d')
        x = np.arange(1, nx, 20)
        y = np.arange(1, ny, 20)
        X, Y = np.meshgrid(x, y)
        zs = np.array([fun(x,y) for x,y in zip(np.ravel(X), np.ravel(Y))])
        Z = zs.reshape(X.shape)

        surf = ax.plot_surface(X, Y, Z,cmap=cmap, linewidth=0.2)
        ax.set_xlabel(labels[0])
        ax.set_ylabel(labels[1]) 
        ax.set_zlabel(labels[2]) 
        if (thetitle):
            title(thetitle);

        'Plot the data points'
        if (points):
            xs = data['xdata']
            ys = data['ydata']
            ax.scatter(xs, ys, 0, c='r', marker='.')
   
        'Plot the color bar'
        cbar=fig.colorbar(surf, shrink=0.5, aspect=15)
        cbar.ax.set_ylabel(labels[2], rotation=90)

    if (output_file):
        plt.savefig(output_file)
    else:
        plt.show()


if __name__ == '__main__':
    main()
