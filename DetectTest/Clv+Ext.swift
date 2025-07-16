
//
//  CollectionView+Ext.swift
//  mvcsample
//
//  Created by Nguyen Dinh Dong on 25/11/2022.
//

import Foundation
import UIKit
import Foundation
import UIKit

protocol ClassNameProtocol {
    static var className: String { get }
    var className: String { get }
}

extension ClassNameProtocol {
    static var className: String {
        return String(describing: self)
    }

    var className: String {
        return type(of: self).className
    }
}

extension NSObject: ClassNameProtocol {}



public extension UICollectionView
{
    
    /// Hàm hỗ trợ đăng kí Cell với Collection
    func register<T: UICollectionViewCell>(cellType: T.Type, bundle: Bundle? = nil)
    {
        let className = cellType.className
        let nib = UINib(nibName: className, bundle: bundle)
        register(nib, forCellWithReuseIdentifier: className)
    }

    /// Hàm hỗ trợ đăng kí mảng cell với Collection
    func register<T: UICollectionViewCell>(cellTypes: [T.Type], bundle: Bundle? = nil)
    {
        cellTypes.forEach { register(cellType: $0, bundle: bundle) }
    }

    /// Hàm hỗ trợ đăng kí UICollectionReusableView với collection
    func register<T: UICollectionReusableView>(reusableViewType: T.Type,
                                               ofKind kind: String = UICollectionView.elementKindSectionHeader,
                                               bundle: Bundle? = nil)
    {
        let className = reusableViewType.className
        let nib = UINib(nibName: className, bundle: bundle)
        register(nib, forSupplementaryViewOfKind: kind, withReuseIdentifier: className)
    }
    
    /// Hàm hỗ trợ đăng kí mảng UICollectionReusableView với collection
    func register<T: UICollectionReusableView>(reusableViewTypes: [T.Type],
                                               ofKind kind: String = UICollectionView.elementKindSectionHeader,
                                               bundle: Bundle? = nil)
    {
        reusableViewTypes.forEach { register(reusableViewType: $0, ofKind: kind, bundle: bundle) }
    }

    /// Hàm hỗ trợ sử dụng lại cell
    func dequeueReusableCell<T: UICollectionViewCell>(with type: T.Type,
                                                      for indexPath: IndexPath) -> T
    {
        return dequeueReusableCell(withReuseIdentifier: type.className, for: indexPath) as! T
    }

    /// Hàm hỗ trợ sử dụng lại UICollectionReusableView
    func dequeueReusableView<T: UICollectionReusableView>(with type: T.Type,
                                                          for indexPath: IndexPath,
                                                          ofKind kind: String = UICollectionView.elementKindSectionHeader) -> T
    {
        return dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: type.className, for: indexPath) as! T
    }
}
