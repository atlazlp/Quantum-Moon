pragma ComponentBehavior: Bound

import QtQuick
import qs.components.images

Item {
    id: root

    required property string path

    CachingImage {
        anchors.fill: parent
        path: root.path
        fillMode: Image.PreserveAspectCrop
    }
}
